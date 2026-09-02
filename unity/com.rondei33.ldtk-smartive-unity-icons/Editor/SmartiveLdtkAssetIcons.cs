using System;
using System.IO;
using UnityEditor;
using UnityEngine;

namespace LDTKSmartive.UnityIcons.Editor
{
    [InitializeOnLoad]
    internal static class SmartiveLdtkAssetIcons
    {
        private static readonly string[] SupportedExtensions = { ".ldtk", ".ldtkl", ".ldtka" };
        private const string IconAssetPath = "Packages/com.rondei33.ldtk-smartive-unity-icons/Editor/SmartiveIcon.png";

        private static Texture2D _icon;

        static SmartiveLdtkAssetIcons()
        {
            EditorApplication.delayCall += RefreshAll;
        }

        [MenuItem("Tools/LDTK-Smartive/Refresh LDtk asset icons")]
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
            foreach (string supportedExtension in SupportedExtensions)
            {
                if (string.Equals(extension, supportedExtension, StringComparison.OrdinalIgnoreCase))
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
            EditorApplication.RepaintProjectWindow();
            EditorApplication.RepaintHierarchyWindow();
            SceneView.RepaintAll();
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
            bool needsRefresh = false;

            foreach (string assetPath in importedAssets)
            {
                if (SmartiveLdtkAssetIcons.IsSupportedAsset(assetPath))
                {
                    needsRefresh = true;
                    break;
                }
            }

            if (!needsRefresh)
            {
                foreach (string assetPath in movedAssets)
                {
                    if (SmartiveLdtkAssetIcons.IsSupportedAsset(assetPath))
                    {
                        needsRefresh = true;
                        break;
                    }
                }
            }

            if (needsRefresh)
            {
                EditorApplication.delayCall += SmartiveLdtkAssetIcons.RefreshAll;
            }
        }
    }
}
