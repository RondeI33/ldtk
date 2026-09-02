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

        // 64px copy of the same Smartive logo used by the desktop builds.
        // Embedded so this tiny UPM package has no runtime or asset-path dependency.
        private const string IconPngBase64 = "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";

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

        internal static void ApplyToAsset(string assetPath)
        {
            if (!IsSupportedAsset(assetPath))
            {
                return;
            }

            UnityEngine.Object asset = AssetDatabase.LoadMainAssetAtPath(assetPath);
            Texture2D icon = GetIcon();
            if (asset == null || icon == null)
            {
                return;
            }

            EditorGUIUtility.SetIconForObject(asset, icon);
        }

        internal static void RefreshAll()
        {
            foreach (string assetPath in AssetDatabase.GetAllAssetPaths())
            {
                ApplyToAsset(assetPath);
            }

            EditorApplication.RepaintProjectWindow();
        }

        internal static void RefreshImportedAssets(string[] importedAssets, string[] movedAssets)
        {
            bool needsRefresh = false;

            foreach (string assetPath in importedAssets)
            {
                if (IsSupportedAsset(assetPath))
                {
                    needsRefresh = true;
                    break;
                }
            }

            if (!needsRefresh)
            {
                foreach (string assetPath in movedAssets)
                {
                    if (IsSupportedAsset(assetPath))
                    {
                        needsRefresh = true;
                        break;
                    }
                }
            }

            if (needsRefresh)
            {
                // Run after all importers have finished assigning their own icons.
                EditorApplication.delayCall += RefreshAll;
            }
        }

        private static Texture2D GetIcon()
        {
            if (_icon != null)
            {
                return _icon;
            }

            byte[] bytes = Convert.FromBase64String(IconPngBase64);
            Texture2D icon = new Texture2D(2, 2, TextureFormat.RGBA32, false)
            {
                name = "LDTK-Smartive",
                hideFlags = HideFlags.HideAndDontSave,
                filterMode = FilterMode.Bilinear
            };

            if (!ImageConversion.LoadImage(icon, bytes, true))
            {
                UnityEngine.Object.DestroyImmediate(icon);
                return null;
            }

            _icon = icon;
            return _icon;
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
            SmartiveLdtkAssetIcons.RefreshImportedAssets(importedAssets, movedAssets);
        }
    }
}
