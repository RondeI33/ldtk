using System.Collections.Generic;
using UnityEditor;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace LDTKSmartive.UnityIcons.Editor
{
    internal static class SmartiveCameraPreviewCapture
    {
        private const float MaxDimensionPixels = 10000000f;

        internal static bool TrySelectCamera(Scene scene, Camera selected, out Camera camera, out string error)
        {
            camera = null;
            error = "";
            if (!scene.IsValid() || !scene.isLoaded)
            {
                error = "There is no loaded active scene.";
                return false;
            }

            if (selected != null)
            {
                if (!IsLoadedGameCamera(selected))
                {
                    error = "Choose an enabled game camera from a loaded scene.";
                    return false;
                }
                camera = selected;
                return true;
            }

            List<Camera> candidates = new List<Camera>();
            List<Camera> mainCameras = new List<Camera>();
            foreach (GameObject root in scene.GetRootGameObjects())
            {
                foreach (Camera candidate in root.GetComponentsInChildren<Camera>(true))
                {
                    if (candidate.gameObject.scene != scene || !IsLoadedGameCamera(candidate))
                    {
                        continue;
                    }

                    candidates.Add(candidate);
                    if (candidate.CompareTag("MainCamera"))
                    {
                        mainCameras.Add(candidate);
                    }
                }
            }

            if (mainCameras.Count == 1)
            {
                camera = mainCameras[0];
                return true;
            }

            if (mainCameras.Count == 0 && candidates.Count == 1)
            {
                camera = candidates[0];
                return true;
            }

            error = candidates.Count == 0
                ? "The active scene has no enabled game camera. Select its persistent or additive-scene output camera explicitly."
                : "The active scene has multiple game cameras. Choose the gameplay camera explicitly.";
            return false;
        }

        private static bool IsLoadedGameCamera(Camera camera)
        {
            const HideFlags excludedFlags = HideFlags.DontSave | HideFlags.HideInHierarchy | HideFlags.HideInInspector;
            return camera != null
                && !EditorUtility.IsPersistent(camera)
                && camera.gameObject.scene.IsValid()
                && camera.gameObject.scene.isLoaded
                && camera.isActiveAndEnabled
                && camera.cameraType == CameraType.Game
                && (camera.hideFlags & excludedFlags) == 0
                && (camera.gameObject.hideFlags & excludedFlags) == 0;
        }

        internal static SmartiveCameraPreviewData Capture(Scene scene, Camera camera, float pixelsPerUnit, bool live)
        {
            SmartiveCameraPreviewData data = new SmartiveCameraPreviewData
            {
                sceneName = scene.IsValid() ? scene.name : "",
                scenePath = scene.IsValid() ? scene.path : "",
                cameraName = camera == null ? "" : camera.name,
                pixelsPerUnit = SmartiveCameraPreviewFiles.IsPositiveFinite(pixelsPerUnit) ? pixelsPerUnit : 0,
                live = live
            };

            if (!scene.IsValid() || !scene.isLoaded)
            {
                return Invalid(data, "There is no loaded active scene.");
            }

            if (!IsLoadedGameCamera(camera))
            {
                return Invalid(data, "Choose an enabled game camera from a loaded scene.");
            }

            data.orthographic = camera.orthographic;

            if (!data.orthographic)
            {
                return Invalid(data, "Camera preview requires an orthographic 2D camera.");
            }

            if (!(Quaternion.Angle(camera.transform.rotation, Quaternion.identity) <= 0.01f))
            {
                return Invalid(data, "Rotated cameras are not supported by the axis-aligned LDtk preview.");
            }

            if (camera.stereoEnabled)
            {
                return Invalid(data, "Stereo cameras are not supported by the 2D preview.");
            }

            if (data.pixelsPerUnit <= 0)
            {
                return Invalid(data, "No valid importer Pixels Per Unit value was found. Set an explicit PPU override.");
            }

            Matrix4x4 actual = camera.projectionMatrix;
            for (int i = 0; i < 16; i++)
            {
                if (!SmartiveCameraPreviewFiles.IsFinite(actual[i]))
                {
                    return Invalid(data, "The camera projection contains a non-finite value.");
                }
            }

            if (actual.m00 <= 0 || actual.m11 <= 0)
            {
                return Invalid(data, "The camera projection must have positive horizontal and vertical scales.");
            }

            // The output projection can include a Pixel Perfect or controller adjustment
            // that differs from the camera's nominal size/aspect properties.
            float horizontalSize = 1f / actual.m00;
            float verticalSize = 1f / actual.m11;
            float aspect = horizontalSize / verticalSize;
            if (!SmartiveCameraPreviewFiles.IsPositiveFinite(horizontalSize)
                || !SmartiveCameraPreviewFiles.IsPositiveFinite(verticalSize)
                || !SmartiveCameraPreviewFiles.IsPositiveFinite(aspect))
            {
                return Invalid(data, "The camera projection has invalid dimensions.");
            }

            data.orthographicSize = verticalSize;
            data.aspect = aspect;
            float pixelHeight = 2 * data.orthographicSize * data.pixelsPerUnit;
            float pixelWidth = pixelHeight * data.aspect;
            if (!SmartiveCameraPreviewFiles.IsPositiveFinite(pixelHeight)
                || !SmartiveCameraPreviewFiles.IsPositiveFinite(pixelWidth)
                || pixelHeight > MaxDimensionPixels || pixelWidth > MaxDimensionPixels)
            {
                return Invalid(data, "The camera dimensions must not exceed 10,000,000 LDtk pixels on either axis.");
            }

            if (!SmartiveCameraPreviewFiles.IsFinite(camera.nearClipPlane)
                || !SmartiveCameraPreviewFiles.IsFinite(camera.farClipPlane)
                || camera.farClipPlane <= camera.nearClipPlane)
            {
                return Invalid(data, "The camera clipping planes are invalid.");
            }

            Matrix4x4 expected = Matrix4x4.Ortho(-horizontalSize, horizontalSize,
                -data.orthographicSize, data.orthographicSize, camera.nearClipPlane, camera.farClipPlane);
            for (int i = 0; i < 16; i++)
            {
                float tolerance = 0.0001f * Mathf.Max(0.000001f, Mathf.Abs(expected[i]));
                if (!SmartiveCameraPreviewFiles.IsFinite(expected[i]) || Mathf.Abs(actual[i] - expected[i]) > tolerance)
                {
                    return Invalid(data, "The camera uses an off-center, skewed or perspective projection that cannot be represented accurately by this preview.");
                }
            }

            data.valid = true;
            return data;
        }

        private static SmartiveCameraPreviewData Invalid(SmartiveCameraPreviewData data, string error)
        {
            data.valid = false;
            data.error = error;
            return data;
        }
    }
}
