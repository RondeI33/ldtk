using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using LDtkUnity;
using LDtkUnity.Editor;
using Newtonsoft.Json.Linq;
using UnityEngine;
using UnityEngine.Tilemaps;

namespace LDTKSmartive.UnityTileRotation
{
    /// <summary>
    /// Native LDtk JSON has two flip bits. Smartive's third transpose bit is
    /// stored per individual tile in World.ldtk-fork.json and restored after
    /// LDtkUnity constructs each Tilemap. No whole-layer transform is changed.
    /// </summary>
    public sealed class SmartiveTileRotationPostprocessor : LDtkPostprocessor
    {
        private static readonly StringComparison PathComparison =
            Application.platform == RuntimePlatform.WindowsEditor
                ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;

        private static readonly Matrix4x4 UnityTranspose = CreateUnityTranspose();

        private static Matrix4x4 CreateUnityTranspose()
        {
            // LDtk screen Y points down; Tilemap Y points up.
            // Screen-space x'=y,y'=x becomes x'=-y,y'=-x in Unity.
            Matrix4x4 m = Matrix4x4.identity;
            m.m00 = 0;
            m.m01 = -1;
            m.m10 = -1;
            m.m11 = 0;
            return m;
        }

        public override int GetPostprocessOrder() => 100;

        protected override void OnPostprocessLevel(GameObject root, LdtkJson projectJson)
        {
            LDtkComponentLevel level = root.GetComponent<LDtkComponentLevel>();
            if (level == null || level.LayerInstances == null || ImportContext == null)
                return;

            string sourcePath = Path.GetFullPath(ImportContext.assetPath);
            string projectPath = ResolveProject(sourcePath, level.Iid == null ? null : level.Iid.Iid);
            if (projectPath == null)
                return;

            string sidecarPath = projectPath + "-fork.json";
            if (!File.Exists(sidecarPath))
                return;

            try
            {
                RegisterDependency(sidecarPath);
                JObject sidecar = JObject.Parse(File.ReadAllText(sidecarPath));
                JObject transforms = sidecar["tileTransforms"] as JObject;
                if (transforms == null)
                    return;

                JObject nativeLevel = FindNativeLevel(sourcePath, projectPath, level.Iid.Iid);
                if (nativeLevel == null)
                {
                    Debug.LogWarning("[LDTK-Smartive] Could not match imported level to source JSON; tile rotation metadata was not applied.");
                    return;
                }

                int applied = 0;
                foreach (LDtkComponentLayer layer in level.LayerInstances)
                {
                    if (layer == null || layer.Type != "Tiles" || layer.Iid == null ||
                        layer.GridTiles == null || layer.GridTiles.Tilemap == null)
                        continue;
                    JObject entry = transforms[layer.Iid.Iid] as JObject;
                    if (entry == null || !(entry["cells"] is JArray cells))
                        continue;

                    JObject nativeLayer = FindNativeLayer(nativeLevel, layer.Iid.Iid);
                    if (!ValidLayer(entry, layer, nativeLayer))
                    {
                        Debug.LogWarning("[LDTK-Smartive] Stale tile rotation metadata for layer " + layer.Identifier +
                            ". The original LDtk tiles were left untouched.");
                        continue;
                    }

                    Tilemap map = layer.GridTiles.Tilemap;
                    var byCoordinate = GroupNativeTiles(nativeLayer["gridTiles"] as JArray);

                    foreach (JToken cell in cells)
                    {
                        int coordId = ReadInt(cell, "coordId", -1);
                        int stackIndex = ReadInt(cell, "stackIndex", -1);
                        int tileId = ReadInt(cell, "tileId", -1);
                        int flips = ReadInt(cell, "flips", -1);
                        int width = layer.CSize.x;
                        int height = layer.CSize.y;
                        if (coordId < 0 || coordId >= width * height ||
                            stackIndex < 0 || flips < 4 || flips > 7 ||
                            !byCoordinate.TryGetValue(coordId, out List<JObject> stack) ||
                            stackIndex >= stack.Count ||
                            ReadInt(stack[stackIndex], "t", -1) != tileId ||
                            ReadInt(stack[stackIndex], "f", -1) != (flips & 3))
                            continue;

                        int cx = coordId % width;
                        int cy = coordId / width;
                        Vector3Int position = new Vector3Int(cx, height - 1 - cy, stackIndex);
                        if (!map.HasTile(position))
                            continue;

                        // Preserve the importer-provided flip, scale and pixel offset.
                        // Append only the missing transpose to this specific cell.
                        Matrix4x4 matrix = map.GetTransformMatrix(position) * UnityTranspose;
                        TileFlags flags = map.GetTileFlags(position);
                        if ((flags & TileFlags.LockTransform) != 0)
                            map.SetTileFlags(position, flags & ~TileFlags.LockTransform);
                        map.SetTransformMatrix(position, matrix);
                        applied++;
                    }
                }

                if (applied > 0)
                    Debug.Log("[LDTK-Smartive] Restored " + applied +
                        " individual 90-degree tile orientations in " + level.Identifier + ".");
            }
            catch (Exception exception)
            {
                Debug.LogError("[LDTK-Smartive] Tile-rotation import failed: " + exception);
            }
        }

        private void RegisterDependency(string fullPath)
        {
            string root = Path.GetFullPath(Path.Combine(Application.dataPath, "..")).Replace('\\', '/').TrimEnd('/');
            string full = Path.GetFullPath(fullPath).Replace('\\', '/');
            if (full.StartsWith(root + "/", PathComparison))
                ImportContext.DependsOnSourceAsset(full.Substring(root.Length + 1));
        }

        private static int ReadInt(JToken token, string field, int fallback)
        {
            JToken value = token?[field];
            return value != null && value.Type == JTokenType.Integer ? (int)value : fallback;
        }

        private static bool ValidLayer(JObject metadata, LDtkComponentLayer layer, JObject source)
        {
            return source != null &&
                ReadInt(metadata, "gridSize", -1) == layer.GridSize &&
                ReadInt(metadata, "gridWidth", -1) == layer.CSize.x &&
                ReadInt(metadata, "gridHeight", -1) == layer.CSize.y &&
                ReadInt(metadata, "layerDefUid", -1) == ReadInt(source, "layerDefUid", -2) &&
                ReadInt(metadata, "tilesetUid", -1) == ReadInt(source, "__tilesetDefUid", -2);
        }

        private static Dictionary<int, List<JObject>> GroupNativeTiles(JArray tiles)
        {
            var grouped = new Dictionary<int, List<JObject>>();
            if (tiles == null) return grouped;
            foreach (JToken item in tiles)
            {
                if (!(item is JObject tile) || !(tile["d"] is JArray d) || d.Count == 0)
                    continue;
                int coordId = d[0].Value<int>();
                if (!grouped.TryGetValue(coordId, out List<JObject> stack))
                    grouped.Add(coordId, stack = new List<JObject>());
                stack.Add(tile);
            }
            return grouped;
        }

        private static JObject FindNativeLayer(JObject level, string iid)
        {
            return (level["layerInstances"] as JArray)?
                .OfType<JObject>()
                .FirstOrDefault(layer => string.Equals((string)layer["iid"], iid, StringComparison.Ordinal));
        }

        private static JObject FindLevelInProject(JObject project, string iid)
        {
            IEnumerable<JObject> levels = (project["levels"] as JArray)?.OfType<JObject>() ??
                Enumerable.Empty<JObject>();
            foreach (JObject world in (project["worlds"] as JArray)?.OfType<JObject>() ??
                         Enumerable.Empty<JObject>())
                levels = levels.Concat((world["levels"] as JArray)?.OfType<JObject>() ??
                                       Enumerable.Empty<JObject>());
            return levels.FirstOrDefault(l => string.Equals((string)l["iid"], iid, StringComparison.Ordinal));
        }

        private static JObject FindNativeLevel(string sourcePath, string projectPath, string iid)
        {
            if (sourcePath.EndsWith(".ldtkl", StringComparison.OrdinalIgnoreCase))
                return JObject.Parse(File.ReadAllText(sourcePath));
            JObject project = JObject.Parse(File.ReadAllText(projectPath));
            return FindLevelInProject(project, iid);
        }

        private static string ResolveProject(string importedPath, string levelIid)
        {
            if (importedPath.EndsWith(".ldtk", StringComparison.OrdinalIgnoreCase))
                return importedPath;
            if (!importedPath.EndsWith(".ldtkl", StringComparison.OrdinalIgnoreCase) ||
                string.IsNullOrEmpty(levelIid))
                return null;

            // External levels are imported as .ldtkl. Resolve their source
            // project by exact IID + relative file path, never by filename alone.
            foreach (string candidate in Directory.EnumerateFiles(Application.dataPath, "*.ldtk",
                         SearchOption.AllDirectories))
            {
                try
                {
                    JObject json = JObject.Parse(File.ReadAllText(candidate));
                    JObject entry = FindLevelInProject(json, levelIid);
                    string rel = (string)entry?["externalRelPath"];
                    if (string.IsNullOrEmpty(rel))
                        continue;
                    string referenced = Path.GetFullPath(Path.Combine(Path.GetDirectoryName(candidate), rel));
                    if (string.Equals(importedPath, referenced, PathComparison))
                        return candidate;
                }
                catch (Exception) { /* Not an LDtk project; try the next candidate. */ }
            }
            return null;
        }
    }
}
