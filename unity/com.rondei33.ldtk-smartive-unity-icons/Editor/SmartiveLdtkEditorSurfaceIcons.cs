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

        static SmartiveLdtkEditorSurfaceIcons()
        {
            EditorApplication.delayCall += RefreshAll;
            EditorApplication.hierarchyWindowItemOnGUI += DrawHierarchyWindowIcon;
            EditorApplication.projectChanged += QueueRefresh;
            EditorApplication.hierarchyChanged += QueueRefresh;
        }

        [MenuItem("Tools/LDTK-Smartive/Refresh Inspector + Hierarchy icons")]
        private static void RefreshFromMenu()
        {
            RefreshAll();
        }

        private static void QueueRefresh()
        {
            EditorApplication.delayCall += RefreshAll;
        }

        private static void RefreshAll()
        {
            ClearAllLdtkObjectIcons();
            EditorApplication.RepaintHierarchyWindow();
            SceneView.RepaintAll();

            // Clear once more after importers/editor caches finish delayed work.
            EditorApplication.delayCall += () =>
            {
                ClearAllLdtkObjectIcons();
                EditorApplication.RepaintHierarchyWindow();
                SceneView.RepaintAll();
            };
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

            // Hierarchy-only visual replacement. Never assign to the GameObject.
            GUI.DrawTexture(iconRect, icon, ScaleMode.ScaleToFit, true);
        }

        internal static void ClearAllLdtkObjectIcons()
        {
            // Clear persistent imported LDtk GameObjects/components that older package
            // revisions or Cammin icon-cache patching may have decorated.
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

            // Clear loaded scene instances and every LDtk component on them.
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
                    if (component != null && SmartiveLdtkAssetIcons.IsLdtkUnityType(component.GetType()))
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
                if (component == null || !SmartiveLdtkAssetIcons.IsLdtkUnityType(component.GetType()))
                {
                    continue;
                }

                foreach (string componentName in HierarchyRootComponentNames)
                {
                    if (string.Equals(component.GetType().Name, componentName, StringComparison.Ordinal))
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
                if (component != null && SmartiveLdtkAssetIcons.IsLdtkUnityType(component.GetType()))
                {
                    return true;
                }
            }

            return false;
        }
    }
}
