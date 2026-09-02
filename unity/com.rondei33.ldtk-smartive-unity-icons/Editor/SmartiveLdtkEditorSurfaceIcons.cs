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
            EditorApplication.hierarchyWindowItemOnGUI += DrawHierarchyWindowIcon;
            EditorApplication.hierarchyChanged += RepaintHierarchy;
        }

        [MenuItem("Tools/LDTK-Smartive/Refresh Project + Inspector + Hierarchy icons")]
        private static void RefreshFromMenu()
        {
            SmartiveLdtkAssetIcons.RefreshAll();
            EditorApplication.RepaintHierarchyWindow();
        }

        private static void RepaintHierarchy()
        {
            EditorApplication.delayCall += EditorApplication.RepaintHierarchyWindow;
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

            // UI-only replacement. Never assign this icon to the GameObject itself,
            // otherwise Unity renders it as a Scene-view gizmo.
            GUI.DrawTexture(iconRect, icon, ScaleMode.ScaleToFit, true);
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
    }
}
