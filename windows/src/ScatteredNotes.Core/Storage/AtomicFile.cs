using System.Text;

namespace ScatteredNotes.Core.Storage;

/// <summary>
/// Writes files so that a crash or power cut leaves either the old file or the new one, never a partial
/// one: the data goes to a temporary file in the same folder, is flushed to disk, then replaces the target.
/// </summary>
public static class AtomicFile
{
    private static readonly UTF8Encoding Utf8NoBom = new(encoderShouldEmitUTF8Identifier: false);

    /// <summary>Delays between retries when another program (sync client, antivirus) has the file open.</summary>
    internal static TimeSpan[] RetryDelays { get; set; } =
        [TimeSpan.FromMilliseconds(50), TimeSpan.FromMilliseconds(150), TimeSpan.FromMilliseconds(400), TimeSpan.FromMilliseconds(1000)];

    public static void WriteAllText(string path, string text) => WriteAllBytes(path, Utf8NoBom.GetBytes(text));

    public static void WriteAllBytes(string path, byte[] data)
    {
        var directory = Path.GetDirectoryName(path) ?? ".";
        // Starts with "." and does not end in ".md", so the note loader never picks it up
        var temp = Path.Combine(directory, $".{Path.GetFileName(path)}.{Guid.NewGuid():N}.tmp");
        try
        {
            using (var stream = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            {
                stream.Write(data);
                stream.Flush(flushToDisk: true);
            }
            WithRetry(() => File.Move(temp, path, overwrite: true));
        }
        finally
        {
            if (File.Exists(temp)) File.Delete(temp);
        }
    }

    /// <summary>Runs a file operation, retrying while the file is locked by another process.</summary>
    public static void WithRetry(Action operation)
    {
        for (var attempt = 0; ; attempt++)
        {
            try
            {
                operation();
                return;
            }
            catch (IOException e) when (IsLocked(e) && attempt < RetryDelays.Length)
            {
                Thread.Sleep(RetryDelays[attempt]);
            }
            catch (UnauthorizedAccessException) when (attempt < RetryDelays.Length && OperatingSystem.IsWindows())
            {
                // Windows reports a file being replaced by a sync client as access denied
                Thread.Sleep(RetryDelays[attempt]);
            }
        }
    }

    /// <summary>Reads a file as UTF-8, dropping a byte order mark. null when it is not valid UTF-8.</summary>
    public static string? ReadUtf8(string path)
    {
        byte[] data = [];
        WithRetry(() => data = File.ReadAllBytes(path));
        try
        {
            var span = data.AsSpan();
            if (span.StartsWith((ReadOnlySpan<byte>)[0xEF, 0xBB, 0xBF])) span = span[3..];
            return new UTF8Encoding(false, throwOnInvalidBytes: true).GetString(span);
        }
        catch (DecoderFallbackException)
        {
            return null;
        }
    }

    private static bool IsLocked(IOException e)
    {
        // ERROR_SHARING_VIOLATION and ERROR_LOCK_VIOLATION
        var code = e.HResult & 0xFFFF;
        return code is 32 or 33;
    }
}
