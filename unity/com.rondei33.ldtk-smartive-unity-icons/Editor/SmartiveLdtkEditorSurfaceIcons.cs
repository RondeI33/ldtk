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
                ClearLegacySceneObjectIcons();
                EditorApplication.RepaintHierarchyWindow();
            };
        }

        private static void RefreshAll()
        {
            RefreshProjectAssetsAndImporters();
            ClearLegacySceneObjectIcons();
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

            // This is the native Project-window replacement. Do not also draw a
            // projectWindowItemOnGUI overlay, because that creates a second icon.
            SmartiveLdtkAssetIcons.ApplyToAsset(assetPath);

            // Keep the working Smartive icon in the importer/settings Inspector header.
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

            // selectionRect.x is Unity's native object-icon slot. Drawing at +16
            // put Smartive beside the original icon. Drawing here replaces it visually
            // without assigning an object icon, so no Scene-view gizmo is created.
            float size = Mathf.Min(16f, selectionRect.height);
            Rect iconRect = new Rect(
                selectionRect.x,
                selectionRect.y + (selectionRect.height - size) * 0.5f,
                size,
                size);

            GUI.DrawTexture(iconRect, icon, ScaleMode.ScaleToFit, true);
        }

        private static void ClearLegacySceneObjectIcons()
        {
            // Older revisions assigned Smartive directly to GameObjects. Unity then
            // rendered those icons as Scene-view gizmos. Clear those assignments;
            // Hierarchy branding is now drawn only in hierarchyWindowItemOnGUI.
            GameObject[] gameObjects = Resources.FindObjectsOfTypeAll<GameObject>();
            foreach (GameObject gameObject in gameObjects)
            {
                if (gameObject == null || EditorUtility.IsPersistent(gameObject))
                {
                    continue;
                }

                if (!gameObject.scene.IsValid() || !gameObject.scene.isLoaded)
                {
                    continue;
                }

                if (IsAnyLdtkGameObject(gameObject))
                {
                    EditorGUIUtility.SetIconForObject(gameObject, null);
                }
            }
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

        private static bool IsAnyLdtkGameObject(GameObject gameObject)
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
