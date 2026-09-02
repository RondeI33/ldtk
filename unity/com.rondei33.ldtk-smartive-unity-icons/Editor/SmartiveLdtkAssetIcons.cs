using System;
using System.Collections;
using System.Linq;
using System.Reflection;
using UnityEditor;
using UnityEngine;

namespace LDTKSmartive.UnityIcons.Editor
{
    [InitializeOnLoad]
    internal static class SmartiveLdtkAssetIcons
    {
        private const string IconAssetPath = "Packages/com.rondei33.ldtk-smartive-unity-icons/Editor/SmartiveIcon.png";
        private static readonly string[] SupportedExtensions = { ".ldtk", ".ldtkl", ".ldtka" };
        private static readonly string[] CamminIconKeys = { "ProjectFile", "ProjectFile_Error", "LevelFile", "LevelFile_Error" };

        private static Texture2D _icon;
        private static bool _refreshing;
        private static bool _reimportedThisDomain;

        static SmartiveLdtkAssetIcons()
        {
            EditorApplication.delayCall += RefreshAll;
        }

        [MenuItem("Tools/LDTK-Smartive/Refresh LDtk native icons")]
        private static void RefreshFromMenu()
        {
            _reimportedThisDomain = false;
            RefreshAll();
        }

        internal static bool IsSupportedAsset(string assetPath)
        {
            if (string.IsNullOrEmpty(assetPath))
            {
                return false;
            }

            string extension = System.IO.Path.GetExtension(assetPath);
            return SupportedExtensions.Any(candidate => string.Equals(candidate, extension, StringComparison.OrdinalIgnoreCase));
        }

        internal static Texture2D GetIcon()
        {
            if (_icon == null)
            {
                _icon = AssetDatabase.LoadAssetAtPath<Texture2D>(IconAssetPath);
            }

            return _icon;
        }

        internal static void RefreshAll()
        {
            if (_refreshing)
            {
                return;
            }

            _refreshing = true;
            try
            {
                Texture2D icon = GetIcon();
                if (icon == null)
                {
                    return;
                }

                PatchCamminIconCache(icon);
                ApplyInspectorImporterIcons(icon);

                if (!_reimportedThisDomain)
                {
                    _reimportedThisDomain = true;
                    ReimportSupportedAssets();
                }

                ClearAllLegacyLdtkObjectIcons();

                EditorApplication.delayCall += () =>
                {
                    PatchCamminIconCache(icon);
                    ApplyInspectorImporterIcons(icon);
                    ClearAllLegacyLdtkObjectIcons();
                    EditorApplication.RepaintProjectWindow();
                    EditorApplication.RepaintHierarchyWindow();
                    SceneView.RepaintAll();
                };
            }
            finally
            {
                _refreshing = false;
            }
        }

        private static void PatchCamminIconCache(Texture2D icon)
        {
            foreach (Assembly assembly in AppDomain.CurrentDomain.GetAssemblies())
            {
                Type utilityType = assembly.GetType("LDtkUnity.Editor.LDtkIconUtility");
                if (utilityType == null)
                {
                    continue;
                }

                FieldInfo cacheField = utilityType.GetField("CachedIcons", BindingFlags.Static | BindingFlags.NonPublic);
                IDictionary cache = cacheField?.GetValue(null) as IDictionary;
                if (cache == null)
                {
                    return;
                }

                foreach (string key in CamminIconKeys)
                {
                    cache[key] = icon;
                }

                return;
            }
        }

        private static void ApplyInspectorImporterIcons(Texture2D icon)
        {
            foreach (string assetPath in AssetDatabase.GetAllAssetPaths())
            {
                if (!IsSupportedAsset(assetPath))
                {
                    continue;
                }

                AssetImporter importer = AssetImporter.GetAtPath(assetPath);
                if (importer != null)
                {
                    EditorGUIUtility.SetIconForObject(importer, icon);
                }
            }
        }

        private static void ReimportSupportedAssets()
        {
            string[] supportedPaths = AssetDatabase.GetAllAssetPaths().Where(IsSupportedAsset).ToArray();
            foreach (string assetPath in supportedPaths)
            {
                AssetDatabase.ImportAsset(assetPath, ImportAssetOptions.ForceUpdate);
            }
        }

        internal static void ClearAllLegacyLdtkObjectIcons()
        {
            GameObject[] gameObjects = Resources.FindObjectsOfTypeAll<GameObject>();
            foreach (GameObject gameObject in gameObjects)
            {
                if (gameObject == null || !IsLdtkGameObject(gameObject))
                {
                    continue;
                }

                EditorGUIUtility.SetIconForObject(gameObject, null);

                Component[] components = gameObject.GetComponents<Component>();
                foreach (Component component in components)
                {
                    if (component != null && IsLdtkUnityType(component.GetType()))
                    {
                        EditorGUIUtility.SetIconForObject(component, null);
                    }
                }
            }

            SceneView.RepaintAll();
        }

        internal static bool IsLdtkGameObject(GameObject gameObject)
        {
            Component[] components = gameObject.GetComponents<Component>();
            foreach (Component component in components)
            {
                if (component != null && IsLdtkUnityType(component.GetType()))
                {
                    return true;
                }
            }

            return false;
        }

        internal static bool IsLdtkUnityType(Type type)
        {
            string typeNamespace = type.Namespace;
            return string.Equals(typeNamespace, "LDtkUnity", StringComparison.Ordinal)
                || (!string.IsNullOrEmpty(typeNamespace)
                    && typeNamespace.StartsWith("LDtkUnity.", StringComparison.Ordinal));
        }
    }

    internal sealed class SmartiveLdtkIconPostprocessor : AssetPostprocessor
    {
        private static void OnPostprocessAllAssets(
            string[] importedAssets,
            string[] deletedAssets,
            string[] movedAssets,
            string[] movedFromAssetPaths)
        {
            bool touchedLdtkAsset = importedAssets.Any(SmartiveLdtkAssetIcons.IsSupportedAsset)
                || movedAssets.Any(SmartiveLdtkAssetIcons.IsSupportedAsset);

            if (!touchedLdtkAsset)
            {
                return;
            }

            EditorApplication.delayCall += SmartiveLdtkAssetIcons.RefreshAll;
        }
    }
}
