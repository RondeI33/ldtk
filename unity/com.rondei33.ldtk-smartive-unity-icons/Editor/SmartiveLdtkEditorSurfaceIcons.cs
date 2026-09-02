using System;
using System.Reflection;
using UnityEditor;
using UnityEngine;

namespace LDTKSmartive.UnityIcons.Editor
{
    [InitializeOnLoad]
    internal static class SmartiveLdtkEditorSurfaceIcons
    {
        private static MethodInfo _getIconMethod;
        private static bool _projectRefreshQueued;
        private static bool _hierarchyRefreshQueued;

        static SmartiveLdtkEditorSurfaceIcons()
        {
            EditorApplication.delayCall += RefreshAll;
            EditorApplication.projectChanged += QueueProjectRefresh;
            EditorApplication.hierarchyChanged += QueueHierarchyRefresh;
            Selection.selectionChanged += RefreshSelection;
        }

        [MenuItem("Tools/LDTK-Smartive/Refresh Inspector + Hierarchy icons")]
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
                RefreshHierarchyObjects();
                RefreshSelection();
                EditorApplication.RepaintHierarchyWindow();
            };
        }

        private static void RefreshAll()
        {
            RefreshProjectAssetsAndImporters();
            RefreshHierarchyObjects();
            RefreshSelection();
            EditorApplication.RepaintProjectWindow();
            EditorApplication.RepaintHierarchyWindow();
        }

        private static void RefreshProjectAssetsAndImporters()
        {
            foreach (string assetPath in AssetDatabase.GetAllAssetPaths())
            {
                if (!SmartiveLdtkAssetIcons.IsSupportedAsset(assetPath))
                {
                    continue;
                }

                ApplyToAssetAndImporter(assetPath);
            }
        }

        private static void ApplyToAssetAndImporter(string assetPath)
        {
            Texture2D icon = GetIcon();
            if (icon == null)
            {
                return;
            }

            SmartiveLdtkAssetIcons.ApplyToAsset(assetPath);

            AssetImporter importer = AssetImporter.GetAtPath(assetPath);
            if (importer != null)
            {
                EditorGUIUtility.SetIconForObject(importer, icon);
            }

            UnityEngine.Object[] allAssets = AssetDatabase.LoadAllAssetsAtPath(assetPath);
            foreach (UnityEngine.Object asset in allAssets)
            {
                if (asset != null && IsLdtkUnityObject(asset))
                {
                    EditorGUIUtility.SetIconForObject(asset, icon);
                }
            }
        }

        private static void RefreshHierarchyObjects()
        {
            Texture2D icon = GetIcon();
            if (icon == null)
            {
                return;
            }

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

                if (IsLdtkGameObject(gameObject))
                {
                    EditorGUIUtility.SetIconForObject(gameObject, icon);
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

            Texture2D icon = GetIcon();
            if (icon == null)
            {
                return;
            }

            if (selected is GameObject selectedGameObject && IsLdtkGameObject(selectedGameObject))
            {
                EditorGUIUtility.SetIconForObject(selectedGameObject, icon);
                return;
            }

            string assetPath = AssetDatabase.GetAssetPath(selected);
            if (SmartiveLdtkAssetIcons.IsSupportedAsset(assetPath))
            {
                ApplyToAssetAndImporter(assetPath);
            }
        }

        private static bool IsLdtkUnityObject(UnityEngine.Object asset)
        {
            if (asset is GameObject gameObject)
            {
                return IsLdtkGameObject(gameObject);
            }

            return IsLdtkUnityType(asset.GetType());
        }

        private static bool IsLdtkGameObject(GameObject gameObject)
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
