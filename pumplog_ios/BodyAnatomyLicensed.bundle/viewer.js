import * as THREE from "three";
import { OrbitControls } from "three/addons/OrbitControls.js";
import { GLTFLoader } from "three/addons/GLTFLoader.js";
import { DRACOLoader } from "three/addons/DRACOLoader.js";

const container = document.getElementById("viewer");
const loading = document.getElementById("loading");
const resetButton = document.getElementById("reset");
const muscleName = document.getElementById("muscle-name");

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(30, 1, 0.01, 100);
const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, powerPreference: "high-performance" });
renderer.setClearColor(0x000000, 0);
renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.2;
container.appendChild(renderer.domElement);

const controls = new OrbitControls(camera, renderer.domElement);
controls.enableDamping = true;
controls.dampingFactor = 0.075;
controls.enablePan = false;
controls.minPolarAngle = Math.PI * 0.18;
controls.maxPolarAngle = Math.PI * 0.82;
controls.rotateSpeed = 0.72;
controls.zoomSpeed = 0.85;

scene.add(new THREE.HemisphereLight(0xffffff, 0x25262b, 2.2));
const keyLight = new THREE.DirectionalLight(0xffeee8, 3.2);
keyLight.position.set(3, 5, 5);
scene.add(keyLight);
const rimLight = new THREE.DirectionalLight(0x9bb6ff, 2.0);
rimLight.position.set(-4, 2, -5);
scene.add(rimLight);

const raycaster = new THREE.Raycaster();
const pointer = new THREE.Vector2();
const muscleMeshes = [];
let modelRoot = null;
let activeGroups = new Set(Array.isArray(window.pumpLogPendingGroups) ? window.pumpLogPendingGroups : []);
let initialCameraPosition = new THREE.Vector3(0, 0, 4);
let initialTarget = new THREE.Vector3(0, 0, 0);
let nameTimer = null;

const groupMatchers = {
    chest: ["pectoralis", "serratus", "subclavius"],
    back: ["trapezius", "latissimus", "rhomboid", "erector spinae", "teres major", "iliocostalis", "longissimus", "spinalis"],
    shoulders: ["deltoid", "supraspinatus", "infraspinatus", "teres minor", "subscapularis"],
    biceps: ["biceps brachii", "biceps", "brachialis", "brachioradialis"],
    triceps: ["triceps brachii", "triceps"],
    legs: [
        "gluteus", "quadriceps", "rectus femoris", "vastus", "biceps femoris",
        "semitendinosus", "semimembranosus", "adductor longus", "adductor magnus",
        "gracilis", "sartorius", "gastrocnemius", "soleus", "tibialis",
        "fibularis", "tensor fasciae latae"
    ],
    abs: ["rectus abdominis", "external oblique", "internal oblique", "transversus abdominis", "quadratus lumborum"]
};

function resize() {
    const width = Math.max(container.clientWidth, 1);
    const height = Math.max(container.clientHeight, 1);
    camera.aspect = width / height;
    camera.updateProjectionMatrix();
    renderer.setSize(width, height, false);
}

function anatomyText(object) {
    const data = object.userData || {};
    return [object.name, data.name, data.nameDetail].filter(Boolean).join(" ").toLowerCase();
}

function muscleGroup(object) {
    const text = anatomyText(object);
    for (const [group, terms] of Object.entries(groupMatchers)) {
        if (terms.some((term) => text.includes(term))) return group;
    }
    return null;
}

function copyMaterial(material) {
    const copy = (item) => {
        const clone = item.clone();
        if (clone.color) clone.userData.pumpLogBaseColor = clone.color.getHex();
        return clone;
    };
    if (Array.isArray(material)) return material.map(copy);
    return copy(material);
}

function visitMaterials(object, callback) {
    const materials = Array.isArray(object.material) ? object.material : [object.material];
    materials.filter(Boolean).forEach(callback);
}

function applyHighlighting() {
    for (const mesh of muscleMeshes) {
        const group = mesh.userData.pumpLogGroup;
        const isActive = group && activeGroups.has(group);
        visitMaterials(mesh, (material) => {
            if (material.color) {
                const baseColor = material.userData?.pumpLogBaseColor ?? 0xbb5a52;
                material.color.set(isActive ? 0xff3b30 : baseColor);
            }
            if (material.emissive) {
                material.emissive.set(isActive ? 0x4b0703 : 0x000000);
                material.emissiveIntensity = isActive ? 0.42 : 0;
            }
            material.transparent = true;
            material.opacity = isActive ? 1 : 0.96;
            material.depthWrite = true;
            material.needsUpdate = true;
        });
    }
}

window.pumpLogSetActiveGroups = function (groups) {
    activeGroups = new Set(Array.isArray(groups) ? groups : []);
    applyHighlighting();
};

function setInitialView(box) {
    const center = box.getCenter(new THREE.Vector3());
    const size = box.getSize(new THREE.Vector3());
    modelRoot.position.sub(center);

    const verticalSize = Math.max(size.y, size.x, size.z);
    const distance = (verticalSize * 0.54) / Math.tan(THREE.MathUtils.degToRad(camera.fov * 0.5));
    initialTarget.set(0, 0, 0);
    initialCameraPosition.set(0, verticalSize * 0.015, distance * 1.08);
    camera.near = Math.max(verticalSize / 1000, 0.01);
    camera.far = verticalSize * 20;
    camera.updateProjectionMatrix();
    controls.minDistance = distance * 0.55;
    controls.maxDistance = distance * 2.0;
    resetView();
}

function resetView() {
    camera.position.copy(initialCameraPosition);
    controls.target.copy(initialTarget);
    controls.update();
}

const dracoLoader = new DRACOLoader();
dracoLoader.setDecoderPath("./libs/draco/");
const loader = new GLTFLoader();
loader.setDRACOLoader(dracoLoader);
loader.load(
    "body.glb?rev=licensed-1",
    (gltf) => {
        modelRoot = gltf.scene;
        modelRoot.traverse((object) => {
            if (!object.isMesh) return;

            const type = String(object.userData?.type || "").toLowerCase();
            const isMuscle = type === "muscle";
            // The licensed source contains bones and connective-tissue helper
            // nodes as well as muscles. Keep the detailed muscle meshes and
            // omit the skeleton so the viewer remains a clear muscle map.
            object.visible = isMuscle;
            if (!isMuscle) return;

            object.material = copyMaterial(object.material);
            object.userData.pumpLogGroup = muscleGroup(object);
            muscleMeshes.push(object);
        });

        scene.add(modelRoot);
        setInitialView(new THREE.Box3().setFromObject(modelRoot));
        applyHighlighting();
        loading.classList.add("hidden");
        resetButton.classList.add("ready");
        setTimeout(() => loading.remove(), 300);
    },
    (progress) => {
        if (progress.total > 0) {
            const percent = Math.min(99, Math.round((progress.loaded / progress.total) * 100));
            loading.querySelector("span").textContent = `人体モデルを読み込み中 ${percent}%`;
        }
    },
    (error) => {
        console.error(error);
        loading.querySelector(".spinner")?.remove();
        loading.querySelector("span").textContent = "人体モデルを読み込めませんでした";
    }
);

function showMuscleName(mesh) {
    const data = mesh.userData || {};
    const displayName = data.name || data.nameDetail || mesh.name;
    if (!displayName) return;
    muscleName.textContent = displayName;
    muscleName.classList.add("visible");
    clearTimeout(nameTimer);
    nameTimer = setTimeout(() => muscleName.classList.remove("visible"), 2200);
}

let pointerDown = null;
renderer.domElement.addEventListener("pointerdown", (event) => {
    pointerDown = { x: event.clientX, y: event.clientY };
});
renderer.domElement.addEventListener("pointerup", (event) => {
    if (!pointerDown || Math.hypot(event.clientX - pointerDown.x, event.clientY - pointerDown.y) > 8) return;
    const rect = renderer.domElement.getBoundingClientRect();
    pointer.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
    pointer.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;
    raycaster.setFromCamera(pointer, camera);
    const hit = raycaster.intersectObjects(muscleMeshes, false)[0];
    if (hit) showMuscleName(hit.object);
});

resetButton.addEventListener("click", resetView);
window.addEventListener("resize", resize);
resize();

function animate() {
    requestAnimationFrame(animate);
    controls.update();
    renderer.render(scene, camera);
}
animate();
