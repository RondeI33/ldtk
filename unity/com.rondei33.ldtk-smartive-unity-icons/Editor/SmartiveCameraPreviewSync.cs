using System;
using System.IO;
using UnityEditor;
using UnityEngine;
using UnityEngine.SceneManagement;
using Object = UnityEngine.Object;

namespace LDTKSmartive.UnityIcons.Editor
{
    public sealed class SmartiveCameraPreviewSync : EditorWindow
    {
        private const double SampleInterval = 0.5;
        private const double HeartbeatInterval = 5;

        [SerializeField] private Object _projectAsset;
        [SerializeField] private Camera _camera;
        [SerializeField] private bool _overridePpu;
        [SerializeField] private float _pixelsPerUnit;
        [SerializeField] private bool _autoSync;

        private double _nextSample;
        private double _lastWrite;
        private string _lastDestination;
        private string _lastSemanticJson;
        private SmartiveCameraPreviewData _lastData;
        private string _status = "Choose the LDtk project used by this scene, then export or enable automatic sync.";
        private MessageType _statusType = MessageType.Info;

        private static string PreferencesKey => "LDTK-Smartive.CameraPreview." + Application.dataPath;

        [MenuItem("Tools/LDTK-Smartive/Camera preview sync")]
        public static void Open()
        {
            SmartiveCameraPreviewSync window = GetWindow<SmartiveCameraPreviewSync>("LDtk camera preview");
            window.minSize = new Vector2(380, 300);
            if (window._projectAsset == null && IsProjectAsset(Selection.activeObject))
            {
                window._projectAsset = Selection.activeObject;
            }
            window.Show();
        }

        private static bool IsProjectAsset(Object asset)
        {
            string path = asset == null ? "" : AssetDatabase.GetAssetPath(asset);
            return string.Equals(Path.GetExtension(path), ".ldtk", StringComparison.OrdinalIgnoreCase);
        }

        private void OnEnable()
        {
            _overridePpu = EditorPrefs.GetBool(PreferencesKey + ".OverridePpu", _overridePpu);
            _pixelsPerUnit = EditorPrefs.GetFloat(PreferencesKey + ".PixelsPerUnit", _pixelsPerUnit);
            if (_projectAsset == null)
            {
                string guid = EditorPrefs.GetString(PreferencesKey + ".Project", "");
                if (!string.IsNullOrEmpty(guid))
                {
                    _projectAsset = AssetDatabase.LoadMainAssetAtPath(AssetDatabase.GUIDToAssetPath(guid));
                }
            }

            EditorApplication.update -= OnEditorUpdate;
            EditorApplication.update += OnEditorUpdate;
            EditorApplication.quitting -= OnEditorQuitting;
            EditorApplication.quitting += OnEditorQuitting;
            _nextSample = 0;
        }

        private void OnDisable()
        {
            EditorApplication.update -= OnEditorUpdate;
            EditorApplication.quitting -= OnEditorQuitting;
            if (_autoSync)
            {
                InvalidateLastDestination("Automatic camera sync stopped. Reopen Camera preview sync in Unity to resume.");
            }
        }

        private void OnEditorQuitting()
        {
            if (_autoSync)
            {
                InvalidateLastDestination("Unity closed. Export a new camera snapshot or resume automatic sync.");
            }
        }

        private void OnGUI()
        {
            EditorGUILayout.LabelField("Camera view in LDtk", EditorStyles.boldLabel);
            EditorGUILayout.HelpBox("Exports the active scene's game camera framing. LDtk uses these dimensions for its camera grid and point preview.", MessageType.Info);

            EditorGUI.BeginChangeCheck();
            Object project = EditorGUILayout.ObjectField("LDtk project", _projectAsset, typeof(Object), false);
            Camera camera = (Camera)EditorGUILayout.ObjectField("Camera (optional)", _camera, typeof(Camera), true);
            bool overridePpu = EditorGUILayout.Toggle("Override Pixels Per Unit", _overridePpu);
            float ppu = _pixelsPerUnit;
            if (overridePpu)
            {
                ppu = EditorGUILayout.FloatField("Pixels Per Unit", ppu);
            }
            else
            {
                float detected;
                bool hasPpu = TryReadImporterPpu(_projectAsset, out detected);
                EditorGUILayout.LabelField("Importer Pixels Per Unit", hasPpu ? detected.ToString("G") : "Unavailable; use an explicit override");
            }

            if (EditorGUI.EndChangeCheck())
            {
                if (_autoSync && project != _projectAsset)
                {
                    InvalidateLastDestination("Camera sync was moved to another LDtk project.");
                }

                _projectAsset = project;
                _camera = camera;
                _overridePpu = overridePpu;
                _pixelsPerUnit = ppu;
                EditorPrefs.SetString(PreferencesKey + ".Project", AssetDatabase.AssetPathToGUID(AssetDatabase.GetAssetPath(_projectAsset)));
                EditorPrefs.SetBool(PreferencesKey + ".OverridePpu", _overridePpu);
                EditorPrefs.SetFloat(PreferencesKey + ".PixelsPerUnit", _pixelsPerUnit);
                _nextSample = 0;
            }

            Scene activeScene = SceneManager.GetActiveScene();
            EditorGUILayout.LabelField("Active scene", activeScene.IsValid() ? activeScene.name : "None");
            Camera resolved;
            string cameraError;
            bool hasCamera = SmartiveCameraPreviewCapture.TrySelectCamera(activeScene, _camera, out resolved, out cameraError);
            EditorGUILayout.LabelField("Source camera", hasCamera ? resolved.name : "No unambiguous camera");

            EditorGUILayout.Space();
            bool autoSync = EditorGUILayout.Toggle("Automatic sync", _autoSync);
            if (autoSync != _autoSync)
            {
                _autoSync = autoSync;
                _nextSample = 0;
                if (!_autoSync)
                {
                    InvalidateLastDestination("Automatic camera sync is off. Export a snapshot to use the current camera settings.");
                }
            }

            if (GUILayout.Button(_autoSync ? "Sync now" : "Export camera snapshot"))
            {
                Sync(true);
            }

            EditorGUILayout.HelpBox(_status, _statusType);
            EditorGUILayout.LabelField("Automatic sync runs while this window is open.\nNo scene, camera, importer or LDtk project settings are modified.", EditorStyles.wordWrappedMiniLabel);
            if (!string.IsNullOrEmpty(_lastDestination))
            {
                EditorGUILayout.SelectableLabel(_lastDestination, EditorStyles.wordWrappedMiniLabel, GUILayout.Height(36));
            }
        }

        private void OnEditorUpdate()
        {
            if (!_autoSync || EditorApplication.timeSinceStartup < _nextSample)
            {
                return;
            }

            _nextSample = EditorApplication.timeSinceStartup + SampleInterval;
            if (EditorApplication.isCompiling || EditorApplication.isUpdating)
            {
                return;
            }

            Sync(false);
        }

        private static bool TryReadImporterPpu(Object asset, out float pixelsPerUnit)
        {
            pixelsPerUnit = 0;
            if (!IsProjectAsset(asset))
            {
                return false;
            }

            AssetImporter importer = AssetImporter.GetAtPath(AssetDatabase.GetAssetPath(asset));
            if (importer == null || !SmartiveLdtkAssetIcons.IsLdtkUnityType(importer.GetType()))
            {
                return false;
            }

            using (SerializedObject serialized = new SerializedObject(importer))
            {
                SerializedProperty property = serialized.FindProperty("_pixelsPerUnit");
                if (property == null)
                {
                    return false;
                }

                if (property.propertyType == SerializedPropertyType.Integer)
                {
                    pixelsPerUnit = property.intValue;
                }
                else if (property.propertyType == SerializedPropertyType.Float)
                {
                    pixelsPerUnit = property.floatValue;
                }
            }

            return SmartiveCameraPreviewFiles.IsPositiveFinite(pixelsPerUnit);
        }

        private bool TryGetDestination(out string destination, out string error)
        {
            destination = null;
            error = "";
            if (!IsProjectAsset(_projectAsset))
            {
                error = "Choose the .ldtk project asset, not a level file or scene object.";
                return false;
            }

            string assetPath = AssetDatabase.GetAssetPath(_projectAsset);
            if (!assetPath.StartsWith("Assets/", StringComparison.Ordinal))
            {
                error = "Choose an LDtk project inside Assets. Package assets are read-only.";
                return false;
            }

            string fullPath = Path.GetFullPath(Path.Combine(Path.GetDirectoryName(Application.dataPath), assetPath));
            if (!File.Exists(fullPath))
            {
                error = "The selected LDtk project no longer exists on disk.";
                return false;
            }

            destination = SmartiveCameraPreviewFiles.GetSidecarPath(fullPath);
            return true;
        }

        private void Sync(bool force)
        {
            try
            {
                string destination;
                string error;
                if (!TryGetDestination(out destination, out error))
                {
                    if (_autoSync)
                    {
                        InvalidateLastDestination(error);
                    }
                    SetStatus(error, MessageType.Warning);
                    return;
                }

                if (_autoSync && !string.IsNullOrEmpty(_lastDestination) && _lastDestination != destination)
                {
                    InvalidateLastDestination("The selected LDtk project moved. Camera sync now uses its new path.");
                }

                float pixelsPerUnit;
                if (_overridePpu)
                {
                    pixelsPerUnit = _pixelsPerUnit;
                }
                else
                {
                    TryReadImporterPpu(_projectAsset, out pixelsPerUnit);
                }

                Scene scene = SceneManager.GetActiveScene();
                Camera camera;
                SmartiveCameraPreviewData data;
                if (SmartiveCameraPreviewCapture.TrySelectCamera(scene, _camera, out camera, out error))
                {
                    data = SmartiveCameraPreviewCapture.Capture(scene, camera, pixelsPerUnit, _autoSync);
                }
                else
                {
                    data = new SmartiveCameraPreviewData
                    {
                        live = _autoSync,
                        sceneName = scene.IsValid() ? scene.name : "",
                        scenePath = scene.IsValid() ? scene.path : "",
                        error = error
                    };
                }

                Write(destination, data, force);
                SetStatus(data.valid
                    ? (_autoSync ? "Camera sync active: " : "Camera snapshot exported: ")
                        + data.cameraName + " • " + (2 * data.orthographicSize * data.aspect * data.pixelsPerUnit).ToString("0.##")
                        + " × " + (2 * data.orthographicSize * data.pixelsPerUnit).ToString("0.##") + " LDtk pixels."
                    : data.error, data.valid ? MessageType.Info : MessageType.Warning);
            }
            catch (Exception exception)
            {
                if (_autoSync)
                {
                    InvalidateLastDestination("Camera capture failed. " + exception.Message);
                }
                SetStatus("Could not sync the camera: " + exception.Message, MessageType.Error);
            }
        }

        private void Write(string destination, SmartiveCameraPreviewData data, bool force)
        {
            data.updatedAtUtc = "";
            string semantic = JsonUtility.ToJson(data);
            double now = EditorApplication.timeSinceStartup;
            if (!force && destination == _lastDestination && semantic == _lastSemanticJson
                && (!_autoSync || now - _lastWrite < HeartbeatInterval))
            {
                return;
            }

            data.updatedAtUtc = DateTime.UtcNow.ToString("O");
            SmartiveCameraPreviewFiles.WriteAtomically(destination, JsonUtility.ToJson(data, true));
            _lastDestination = destination;
            _lastSemanticJson = semantic;
            _lastData = data;
            _lastWrite = now;
        }

        private void InvalidateLastDestination(string error)
        {
            if (string.IsNullOrEmpty(_lastDestination) || _lastData == null)
            {
                return;
            }

            try
            {
                SmartiveCameraPreviewData invalid = JsonUtility.FromJson<SmartiveCameraPreviewData>(JsonUtility.ToJson(_lastData));
                invalid.valid = false;
                invalid.live = false;
                invalid.error = error;
                Write(_lastDestination, invalid, false);
                SetStatus(error, MessageType.Info);
            }
            catch (Exception exception)
            {
                SetStatus("Could not update camera sync status: " + exception.Message, MessageType.Error);
            }
        }

        private void SetStatus(string text, MessageType type)
        {
            if (_status == text && _statusType == type)
            {
                return;
            }
            _status = text;
            _statusType = type;
            Repaint();
        }
    }
}
