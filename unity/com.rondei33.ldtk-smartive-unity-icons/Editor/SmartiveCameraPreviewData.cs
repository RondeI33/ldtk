using System;
using System.IO;
using System.Runtime.CompilerServices;
using System.Text;

[assembly: InternalsVisibleTo("RondeI33.LDTKSmartive.UnityIcons.Editor.Tests")]

namespace LDTKSmartive.UnityIcons.Editor
{
    [Serializable]
    internal sealed class SmartiveCameraPreviewData
    {
        public int schemaVersion = 1;
        public string source = "unity";
        public bool valid;
        public bool orthographic;
        public float orthographicSize;
        public float aspect;
        public float pixelsPerUnit;
        public string sceneName = "";
        public string scenePath = "";
        public string cameraName = "";
        public string updatedAtUtc = "";
        public bool live;
        public string error = "";
    }

    internal static class SmartiveCameraPreviewFiles
    {
        internal static bool IsFinite(float value)
        {
            return !float.IsNaN(value) && !float.IsInfinity(value);
        }

        internal static bool IsPositiveFinite(float value)
        {
            return IsFinite(value) && value > 0;
        }

        internal static string GetSidecarPath(string projectPath)
        {
            if (string.IsNullOrEmpty(projectPath)
                || !string.Equals(Path.GetExtension(projectPath), ".ldtk", StringComparison.OrdinalIgnoreCase))
            {
                throw new ArgumentException("Choose an LDtk project (.ldtk).", nameof(projectPath));
            }

            string absolute = Path.GetFullPath(projectPath);
            return absolute.Substring(0, absolute.Length - ".ldtk".Length) + ".ldtk-camera.json";
        }

        internal static void WriteAtomically(string destination, string json)
        {
            string temporary = destination + ".tmp-" + Guid.NewGuid().ToString("N");
            try
            {
                using (FileStream stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                using (StreamWriter writer = new StreamWriter(stream, new UTF8Encoding(false)))
                {
                    writer.Write(json);
                    writer.Flush();
                    stream.Flush(true);
                }

                if (File.Exists(destination))
                {
                    File.Replace(temporary, destination, null);
                }
                else
                {
                    File.Move(temporary, destination);
                }
            }
            finally
            {
                if (File.Exists(temporary))
                {
                    File.Delete(temporary);
                }
            }
        }
    }
}
