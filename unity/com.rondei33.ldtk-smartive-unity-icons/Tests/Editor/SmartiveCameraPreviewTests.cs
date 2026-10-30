using System;
using System.IO;
using NUnit.Framework;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace LDTKSmartive.UnityIcons.Editor.Tests
{
    public sealed class SmartiveCameraPreviewTests
    {
        private Scene _previousScene;
        private Scene _testScene;
        private Scene _otherScene;
        private string _temporaryDirectory;

        [SetUp]
        public void SetUp()
        {
            _previousScene = SceneManager.GetActiveScene();
            _testScene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Additive);
            SceneManager.SetActiveScene(_testScene);
            _temporaryDirectory = Path.Combine(Path.GetTempPath(), "smartive-camera-tests-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(_temporaryDirectory);
        }

        [TearDown]
        public void TearDown()
        {
            if (_previousScene.IsValid() && _previousScene.isLoaded)
            {
                SceneManager.SetActiveScene(_previousScene);
            }
            if (_otherScene.IsValid() && _otherScene.isLoaded)
            {
                EditorSceneManager.CloseScene(_otherScene, true);
            }
            if (_testScene.IsValid() && _testScene.isLoaded)
            {
                EditorSceneManager.CloseScene(_testScene, true);
            }
            if (Directory.Exists(_temporaryDirectory))
            {
                Directory.Delete(_temporaryDirectory, true);
            }
        }

        private Camera CreateCamera(string name = "Gameplay")
        {
            Camera camera = new GameObject(name).AddComponent<Camera>();
            SceneManager.MoveGameObjectToScene(camera.gameObject, _testScene);
            camera.orthographic = true;
            camera.orthographicSize = 5.625f;
            camera.aspect = 16f / 9f;
            return camera;
        }

        [TestCase("World.ldtk", "World.ldtk-camera.json")]
        [TestCase("World.v2.LDTK", "World.v2.ldtk-camera.json")]
        public void SidecarPathMatchesEditorContract(string projectName, string expectedName)
        {
            Assert.That(SmartiveCameraPreviewFiles.GetSidecarPath(Path.Combine(_temporaryDirectory, projectName)),
                Is.EqualTo(Path.Combine(_temporaryDirectory, expectedName)));
        }

        [TestCase("World.ldtkl")]
        [TestCase("World.json")]
        [TestCase("")]
        public void SidecarPathRejectsNonProjectFiles(string path)
        {
            Assert.Throws<ArgumentException>(() => SmartiveCameraPreviewFiles.GetSidecarPath(path));
        }

        [Test]
        public void AtomicWritesReplaceWholePayloadWithoutTemporaryFiles()
        {
            string path = Path.Combine(_temporaryDirectory, "World.ldtk-camera.json");
            SmartiveCameraPreviewFiles.WriteAtomically(path, "{\"valid\":true,\"cameraName\":\"Kamera żółta\"}");
            SmartiveCameraPreviewFiles.WriteAtomically(path, "{\"valid\":false}");
            Assert.That(File.ReadAllText(path), Is.EqualTo("{\"valid\":false}"));
            Assert.That(Directory.GetFiles(_temporaryDirectory), Has.Length.EqualTo(1));
            Assert.That(File.ReadAllBytes(path)[0], Is.EqualTo((byte)'{'), "JSON should not have a byte-order mark.");
        }

        [Test]
        public void CaptureProducesCurrentAspectAndPpuWithoutChangingCamera()
        {
            Camera camera = CreateCamera();
            Matrix4x4 projection = camera.projectionMatrix;
            Vector3 position = camera.transform.position;
            SmartiveCameraPreviewData data = SmartiveCameraPreviewCapture.Capture(_testScene, camera, 16, true);
            Assert.That(data.valid, Is.True, data.error);
            Assert.That(2 * data.orthographicSize * data.pixelsPerUnit, Is.EqualTo(180).Within(0.0001));
            Assert.That(2 * data.orthographicSize * data.pixelsPerUnit * data.aspect, Is.EqualTo(320).Within(0.0001));
            Assert.That(data.live, Is.True);
            Assert.That(camera.projectionMatrix, Is.EqualTo(projection));
            Assert.That(camera.transform.position, Is.EqualTo(position));
            Assert.That(camera.orthographicSize, Is.EqualTo(5.625f));
            camera.aspect = 4f / 3f;
            data = SmartiveCameraPreviewCapture.Capture(_testScene, camera, 16, false);
            Assert.That(data.valid, Is.True, data.error);
            Assert.That(2 * data.orthographicSize * data.pixelsPerUnit * data.aspect, Is.EqualTo(240).Within(0.0001));
            Assert.That(data.live, Is.False);
        }

        [Test]
        public void AutomaticSelectionPrefersUniqueMainCameraAndRejectsAmbiguity()
        {
            Camera camera = CreateCamera();
            Camera chosen;
            string error;
            Assert.That(SmartiveCameraPreviewCapture.TrySelectCamera(_testScene, null, out chosen, out error), Is.True, error);
            Assert.That(chosen, Is.SameAs(camera));
            Camera second = CreateCamera("UI camera");
            Assert.That(SmartiveCameraPreviewCapture.TrySelectCamera(_testScene, null, out chosen, out error), Is.False);
            camera.tag = "MainCamera";
            Assert.That(SmartiveCameraPreviewCapture.TrySelectCamera(_testScene, null, out chosen, out error), Is.True, error);
            Assert.That(chosen, Is.SameAs(camera));
            second.tag = "MainCamera";
            Assert.That(SmartiveCameraPreviewCapture.TrySelectCamera(_testScene, null, out chosen, out error), Is.False);
            Assert.That(SmartiveCameraPreviewCapture.TrySelectCamera(_testScene, camera, out chosen, out error), Is.True, error);
        }

        [Test]
        public void ExplicitLoadedCameraCanServeAnotherSceneWhileAutomaticLookupStaysScoped()
        {
            Camera camera = CreateCamera();
            camera.enabled = false;
            Assert.That(SmartiveCameraPreviewCapture.Capture(_testScene, camera, 16, true).valid, Is.False);
            Camera chosen;
            string error;
            Assert.That(SmartiveCameraPreviewCapture.TrySelectCamera(_testScene, camera, out chosen, out error), Is.False);
            camera.enabled = true;
            camera.hideFlags = HideFlags.HideInInspector;
            Assert.That(SmartiveCameraPreviewCapture.TrySelectCamera(_testScene, camera, out chosen, out error), Is.False);
            camera.hideFlags = HideFlags.None;
            _otherScene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Additive);
            Assert.That(SmartiveCameraPreviewCapture.TrySelectCamera(_otherScene, null, out chosen, out error), Is.False);
            Assert.That(error, Does.Contain("persistent"));
            Assert.That(SmartiveCameraPreviewCapture.TrySelectCamera(_otherScene, camera, out chosen, out error), Is.True, error);
            Assert.That(chosen, Is.SameAs(camera));
            SmartiveCameraPreviewData data = SmartiveCameraPreviewCapture.Capture(_otherScene, chosen, 16, true);
            Assert.That(data.valid, Is.True, data.error);
            Assert.That(data.sceneName, Is.EqualTo(_otherScene.name));
            Assert.That(data.scenePath, Is.EqualTo(_otherScene.path));
            Assert.That(data.cameraName, Is.EqualTo(camera.name));
        }

        [TestCase(0)]
        [TestCase(-16)]
        [TestCase(float.NaN)]
        [TestCase(float.PositiveInfinity)]
        public void InvalidPpuProducesUnavailablePayload(float ppu)
        {
            SmartiveCameraPreviewData data = SmartiveCameraPreviewCapture.Capture(_testScene, CreateCamera(), ppu, true);
            Assert.That(data.valid, Is.False);
            Assert.That(data.pixelsPerUnit, Is.EqualTo(0));
            Assert.That(data.error, Does.Contain("Pixels Per Unit"));
            Assert.That(JsonUtility.ToJson(data), Does.Not.Contain("NaN").And.Not.Contain("Infinity"));
        }

        [Test]
        public void PerspectiveAndRotationAreRejected()
        {
            Camera camera = CreateCamera();
            camera.orthographic = false;
            Assert.That(SmartiveCameraPreviewCapture.Capture(_testScene, camera, 16, true).error, Does.Contain("orthographic"));
            camera.orthographic = true;
            camera.transform.rotation = Quaternion.Euler(0, 0, 15);
            Assert.That(SmartiveCameraPreviewCapture.Capture(_testScene, camera, 16, true).error, Does.Contain("Rotated"));
        }

        [Test]
        public void CenteredFinalProjectionAdjustmentsAreCapturedWithoutChangingDeclaredLens()
        {
            Camera camera = CreateCamera();
            Matrix4x4 projection = camera.projectionMatrix;
            projection.m00 *= 2;
            projection.m11 *= 1.5f;
            camera.projectionMatrix = projection;
            SmartiveCameraPreviewData data = SmartiveCameraPreviewCapture.Capture(_testScene, camera, 16, true);
            Assert.That(data.valid, Is.True, data.error);
            Assert.That(2 * data.orthographicSize * data.pixelsPerUnit, Is.EqualTo(120).Within(0.0001));
            Assert.That(2 * data.orthographicSize * data.pixelsPerUnit * data.aspect, Is.EqualTo(160).Within(0.0001));
            Assert.That(camera.orthographicSize, Is.EqualTo(5.625f));
            Assert.That(camera.aspect, Is.EqualTo(16f / 9f));
            Assert.That(camera.projectionMatrix, Is.EqualTo(projection));
        }

        [TestCase(0, 1)]
        [TestCase(0, 3)]
        [TestCase(1, 3)]
        [TestCase(3, 2)]
        public void SkewOffCenterAndPerspectiveProjectionTermsAreRejected(int row, int column)
        {
            Camera camera = CreateCamera();
            Matrix4x4 projection = camera.projectionMatrix;
            projection[row, column] += 0.1f;
            camera.projectionMatrix = projection;
            SmartiveCameraPreviewData data = SmartiveCameraPreviewCapture.Capture(_testScene, camera, 16, true);
            Assert.That(data.valid, Is.False);
            Assert.That(data.error, Does.Contain("projection"));
        }

        [Test]
        public void PixelDimensionsAreBoundedToMatchLdtkReader()
        {
            Camera camera = CreateCamera();
            SmartiveCameraPreviewData data = SmartiveCameraPreviewCapture.Capture(_testScene, camera, 1000000, true);
            Assert.That(data.valid, Is.False);
            Assert.That(data.error, Does.Contain("10,000,000"));
        }
    }
}
