using System;
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
                RefreshImporterIcons();
                ClearAllLdtkObjectIcons();
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
                ClearAllLdtkObjectIcons();
                EditorApplication.RepaintHierarchyWindow();
                SceneView.RepaintAll();
            };
        }

        private static void RefreshAll()
        {
            RefreshImporterIcons();
            ClearAllLdtkObjectIcons();
            RefreshSelection();
            EditorApplication.RepaintProjectWindow();
            EditorApplication.RepaintHierarchyWindow();
            SceneView.RepaintAll();

            // Run once more after importers/editor caches finish their delayed work.
            EditorApplication.delayCall += () =>
            {
                ClearAllLdtkObjectIcons();
                EditorApplication.RepaintProjectWindow();
                EditorApplication.RepaintHierarchyWindow();
                SceneView.RepaintAll();
            };
        }

        private static void RefreshImporterIcons()
        {
            Texture2D icon = SmartiveLdtkAssetIcons.GetIcon();
            if (icon == null)
            {
                return;
            }

            foreach (string assetPath in AssetDatabase.GetAllAssetPaths())
            {
                if (!SmartiveLdtkAssetIcons.IsSupportedAsset(assetPath))
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

        private static void RefreshSelection()
        {
            UnityEngine.Object selected = Selection.activeObject;
            if (selected == null)
            {
                return;
            }

            string assetPath = AssetDatabase.GetAssetPath(selected);
            if (!SmartiveLdtkAssetIcons.IsSupportedAsset(assetPath))
            {
                return;
            }

            Texture2D icon = SmartiveLdtkAssetIcons.GetIcon();
            AssetImporter importer = AssetImporter.GetAtPath(assetPath);
            if (importer != null && icon != null)
            {
                EditorGUIUtility.SetIconForObject(importer, icon);
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

            Texture2D icon = SmartiveLdtkAssetIcons.GetIcon();
            if (icon == null)
            {
                return;
            }

            Rect iconRect;
            if (selectionRect.height <= 20f)
            {
                float size = Mathf.Min(16f, selectionRect.height);
                iconRect = new Rect(
                    selectionRect.x,
                    selectionRect.y + (selectionRect.height - size) * 0.5f,
                    size,
                    size);
            }
            else
            {
                float maxWidth = Mathf.Max(16f, selectionRect.width - 8f);
                float maxHeight = Mathf.Max(16f, selectionRect.height - 20f);
                float size = Mathf.Min(64f, Mathf.Min(maxWidth, maxHeight));
                iconRect = new Rect(
                    selectionRect.x + (selectionRect.width - size) * 0.5f,
                    selectionRect.y + 2f,
                    size,
                    size);
            }

            // Draw exactly in Unity's native icon/thumbnail area. The Smartive PNG is
            // opaque, so this visually replaces Cammin's icon rather than appearing beside it.
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

            Texture2D icon = SmartiveLdtkAssetIcons.GetIcon();
            if (icon == null)
            {
                return;
            }

            float size = Mathf.Min(16f, selectionRect.height);
            Rect iconRect = new Rect(
                selectionRect.x,
                selectionRect.y + (selectionRect.height - size) * 0.5f,
                size,
                size);

            GUI.DrawTexture(iconRect, icon, ScaleMode.ScaleToFit, true);
        }

        private static void ClearAllLdtkObjectIcons()
        {
            // Clear persistent imported GameObjects/components left by older package revisions.
            foreach (string assetPath in AssetDatabase.GetAllAssetPaths())
            {
                if (!SmartiveLdtkAssetIcons.IsSupportedAsset(assetPath))
                {
                    continue;
                }

                UnityEngine.Object[] importedObjects = AssetDatabase.LoadAllAssetsAtPath(assetPath);
                foreach (UnityEngine.Object importedObject in importedObjects)
                {
                    if (importedObject is GameObject || importedObject is Component)
                    {
                        EditorGUIUtility.SetIconForObject(importedObject, null);
                    }
                }
            }

            // Clear scene instances and their LDtk components as well.
            GameObject[] gameObjects = Resources.FindObjectsOfTypeAll<GameObject>();
            foreach (GameObject gameObject in gameObjects)
            {
                if (gameObject == null || EditorUtility.IsPersistent(gameObject))
                {
                    continue;
                }

                if (!gameObject.scene.IsValid() || !gameObject.scene.isLoaded || !IsAnyLdtkGameObject(gameObject))
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
    }
}
