using System;
using System.Reflection;
using UnityEditor;
using UnityEngine;

namespace LDTKSmartive.UnityIcons.Editor
{
    [InitializeOnLoad]
    internal static class SmartiveLdtkEditorSurfaceIcons
    {
        private static readonly string[] HierarchyRootComponentNames =
        {
            "LDtkComponentProject",
            "LDtkComponentWorld",
            "LDtkComponentLevel"
        };

        private static MethodInfo _getIconMethod;
        private static bool _projectRefreshQueued;
        private static bool _hierarchyRefreshQueued;

        static SmartiveLdtkEditorSurfaceIcons()
        {
            EditorApplication.delayCall += RefreshAll;
            EditorApplication.projectChanged += QueueProjectRefresh;
            EditorApplication.hierarchyChanged += QueueHierarchyRefresh;
            EditorApplication.projectWindowItemOnGUI += DrawProjectWindowIcon;
            EditorApplication.hierarchyWindowItemOnGUI += DrawHierarchyWindowIcon;
            Selection.selectionChanged += RefreshSelection;
        }

        [MenuItem("Tools/LDTK-Smartive/Refresh Project + Inspector + Hierarchy icons")]
        private static void RefreshFromMenu()
        {
            RefreshAll();
        }

        private static void QueueProjectRefresh()
        {
            if (_projectRefreshQueued)
            {
                return;
            }

            _projectRefreshQueued = true;
            EditorApplication.delayCall += () =>
            {
                _projectRefreshQueued = false;
                RefreshProjectAssetsAndImporters();
                RefreshSelection();
                EditorApplication.RepaintProjectWindow();
            };
        }

        private static void QueueHierarchyRefresh()
        {
            if (_hierarchyRefreshQueued)
            {
                return;
            }

            _hierarchyRefreshQueued = true;
            EditorApplication.delayCall += () =>
            {
                _hierarchyRefreshQueued = false;
                EditorApplication.RepaintHierarchyWindow();
            };
        }

        private static void RefreshAll()
        {
            RefreshProjectAssetsAndImporters();
            RefreshSelection();
            EditorApplication.RepaintProjectWindow();
            EditorApplication.RepaintHierarchyWindow();
        }

        private static void RefreshProjectAssetsAndImporters()
        {
            foreach (string assetPath in AssetDatabase.GetAllAssetPaths())
            {
                if (SmartiveLdtkAssetIcons.IsSupportedAsset(assetPath))
                {
                    ApplyToAssetAndImporter(assetPath);
                }
            }
        }

        private static void ApplyToAssetAndImporter(string assetPath)
        {
            Texture2D icon = GetIcon();
            if (icon == null)
            {
                return;
            }

            // Keep the existing asset/importer icon behavior because this is what
            // makes the Smartive logo appear in the Inspector header.
            SmartiveLdtkAssetIcons.ApplyToAsset(assetPath);

            AssetImporter importer = AssetImporter.GetAtPath(assetPath);
            if (importer != null)
            {
                EditorGUIUtility.SetIconForObject(importer, icon);
            }
        }

        private static void RefreshSelection()
        {
            UnityEngine.Object selected = Selection.activeObject;
            if (selected == null)
            {
                return;
            }

            string assetPath = AssetDatabase.GetAssetPath(selected);
            if (SmartiveLdtkAssetIcons.IsSupportedAsset(assetPath))
            {
                ApplyToAssetAndImporter(assetPath);
            }
        }

        private static void DrawProjectWindowIcon(string guid, Rect selectionRect)
        {
            if (Event.current.type != EventType.Repaint)
            {
                return;
            }

            string assetPath = AssetDatabase.GUIDToAssetPath(guid);
            if (!SmartiveLdtkAssetIcons.IsSupportedAsset(assetPath))
            {
                return;
            }

            Texture2D icon = GetIcon();
            if (icon == null)
            {
                return;
            }

            Rect iconRect;
            if (selectionRect.height <= 20f)
            {
                // Project Browser list mode: cover the normal file icon.
                iconRect = new Rect(selectionRect.x, selectionRect.y, 16f, 16f);
            }
            else
            {
                // Project Browser grid mode: draw a proper thumbnail-sized Smartive logo.
                float availableWidth = Mathf.Max(16f, selectionRect.width - 8f);
                float availableHeight = Mathf.Max(16f, selectionRect.height - 20f);
                float size = Mathf.Min(64f, Mathf.Min(availableWidth, availableHeight));
                iconRect = new Rect(
                    selectionRect.x + (selectionRect.width - size) * 0.5f,
                    selectionRect.y + 2f,
                    size,
                    size);
            }

            GUI.DrawTexture(iconRect, icon, ScaleMode.ScaleToFit, true);
        }

        private static void DrawHierarchyWindowIcon(int instanceId, Rect selectionRect)
        {
            if (Event.current.type != EventType.Repaint)
            {
                return;
            }

            GameObject gameObject = EditorUtility.InstanceIDToObject(instanceId) as GameObject;
            if (gameObject == null || !IsHierarchyLdtkRoot(gameObject))
            {
                return;
            }

            Texture2D icon = GetIcon();
            if (icon == null)
            {
                return;
            }

            // Draw only inside the Hierarchy UI. Do NOT call SetIconForObject on
            // GameObjects because Unity also renders those object icons as Scene-view gizmos.
            Rect iconRect = new Rect(selectionRect.x + 16f, selectionRect.y, 16f, 16f);
            GUI.DrawTexture(iconRect, icon, ScaleMode.ScaleToFit, true);
        }

        private static bool IsHierarchyLdtkRoot(GameObject gameObject)
        {
            Component[] components = gameObject.GetComponents<Component>();
            foreach (Component component in components)
            {
                if (component == null)
                {
                    continue;
                }

                Type type = component.GetType();
                if (!IsLdtkUnityType(type))
                {
                    continue;
                }

                foreach (string componentName in HierarchyRootComponentNames)
                {
                    if (string.Equals(type.Name, componentName, StringComparison.Ordinal))
                    {
                        return true;
                    }
                }
            }

            return false;
        }

        private static bool IsLdtkUnityType(Type type)
        {
            string typeNamespace = type.Namespace;
            return string.Equals(typeNamespace, "LDtkUnity", StringComparison.Ordinal)
                || (!string.IsNullOrEmpty(typeNamespace)
                    && typeNamespace.StartsWith("LDtkUnity.", StringComparison.Ordinal));
        }

        private static Texture2D GetIcon()
        {
            if (_getIconMethod == null)
            {
                _getIconMethod = typeof(SmartiveLdtkAssetIcons).GetMethod(
                    "GetIcon",
                    BindingFlags.Static | BindingFlags.NonPublic);
            }

            if (_getIconMethod == null)
            {
                return null;
            }

            return _getIconMethod.Invoke(null, null) as Texture2D;
        }
    }
}
