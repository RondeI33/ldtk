using System;
using System.IO;
using UnityEditor;
using UnityEngine;

namespace LDTKSmartive.UnityIcons.Editor
{
    [InitializeOnLoad]
    internal static class SmartiveLdtkAssetIcons
    {
        private const string IconAssetPath = "Packages/com.rondei33.ldtk-smartive-unity-icons/Editor/SmartiveIcon.png";
        private static readonly string[] SupportedExtensions = { ".ldtk", ".ldtkl", ".ldtka" };

        private static Texture2D _icon;

        static SmartiveLdtkAssetIcons()
        {
            EditorApplication.delayCall += RefreshAll;
        }

        [MenuItem("Tools/LDTK-Smartive/Refresh LDtk icons")]
        private static void RefreshFromMenu()
        {
            RefreshAll();
        }

        internal static bool IsSupportedAsset(string assetPath)
        {
            if (string.IsNullOrEmpty(assetPath))
            {
                return false;
            }

            string extension = Path.GetExtension(assetPath);
            foreach (string candidate in SupportedExtensions)
            {
                if (string.Equals(candidate, extension, StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }
            }

            return false;
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
            Texture2D icon = GetIcon();
            if (icon != null)
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

            SmartiveLdtkEditorSurfaceIcons.ClearAllLdtkObjectIcons();
            EditorApplication.RepaintProjectWindow();
            EditorApplication.RepaintHierarchyWindow();
            SceneView.RepaintAll();
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
            bool touchedLdtkAsset = false;

            foreach (string assetPath in importedAssets)
            {
                if (SmartiveLdtkAssetIcons.IsSupportedAsset(assetPath))
                {
                    touchedLdtkAsset = true;
                    break;
                }
            }

            if (!touchedLdtkAsset)
            {
                foreach (string assetPath in movedAssets)
                {
                    if (SmartiveLdtkAssetIcons.IsSupportedAsset(assetPath))
                    {
                        touchedLdtkAsset = true;
                        break;
                    }
                }
            }

            if (touchedLdtkAsset)
            {
                EditorApplication.delayCall += SmartiveLdtkAssetIcons.RefreshAll;
            }
        }
    }
}
