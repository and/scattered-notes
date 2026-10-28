using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace ScatteredNotes.Core.Agenda;

/// <summary>
/// Remembers when each checklist or dated line of a note first appeared, so relative words such as
/// "tomorrow" keep the day they were written for, however much the note is edited later.
///
/// Stored as <c>.agenda-log.json</c> in the notes folder, in the same format as the Mac app:
/// <c>{ "notes": { "&lt;note id&gt;": { "&lt;line key&gt;": { "line": "...", "firstSeen": "2026-10-27T06:55:00Z" } } } }</c>
/// It is derived data: if it is missing or corrupt it is rebuilt, and notes are never affected.
/// </summary>
public sealed class AgendaLog
{
    public const string FileName = ".agenda-log.json";

    /// <summary><c>DoneAt</c> is when the Mac app saw the line ticked. This app keeps it as it is, so it isn't lost.</summary>
    public sealed record Entry(
        [property: JsonPropertyName("line")] string Line,
        [property: JsonPropertyName("firstSeen"), JsonConverter(typeof(SecondsDateConverter))] DateTimeOffset FirstSeen,
        [property: JsonPropertyName("doneAt"), JsonConverter(typeof(OptionalSecondsDateConverter)),
         JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] DateTimeOffset? DoneAt = null);

    [JsonPropertyName("notes")]
    public Dictionary<string, Dictionary<string, Entry>> Notes { get; set; } = [];

    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    public static AgendaLog? Decode(byte[] data)
    {
        try
        {
            var log = JsonSerializer.Deserialize<AgendaLog>(data, JsonOptions);
            if (log?.Notes is null) return null;
            // Keys are compared as the Mac app writes them
            log.Notes = log.Notes.ToDictionary(n => n.Key.ToUpperInvariant(), n => n.Value);
            return log;
        }
        catch (Exception)
        {
            // Any unreadable log is rebuilt from the notes
            return null;
        }
    }

    /// <summary>Sorted keys, so the file only changes when its content does.</summary>
    public byte[] Encode()
    {
        var sorted = new SortedDictionary<string, SortedDictionary<string, Entry>>(StringComparer.Ordinal);
        foreach (var (id, entries) in Notes)
            sorted[id] = new SortedDictionary<string, Entry>(entries, StringComparer.Ordinal);
        return JsonSerializer.SerializeToUtf8Bytes(new { notes = sorted }, JsonOptions);
    }

    public Dictionary<string, DateTimeOffset> Anchors(Guid noteId) =>
        Notes.TryGetValue(Models.Note.FormatId(noteId), out var entries)
            ? entries.ToDictionary(e => e.Key, e => e.Value.FirstSeen)
            : [];

    /// <summary>
    /// Syncs a note's entries with its current lines. New lines are stamped <paramref name="seenAt"/>,
    /// existing ones keep their date, and lines no longer present are dropped. Returns whether the log changed.
    /// </summary>
    public bool Update(Guid noteId, IEnumerable<(string Key, string Line)> lines, DateTimeOffset seenAt)
    {
        var id = Models.Note.FormatId(noteId);
        Notes.TryGetValue(id, out var before);
        var entries = before is null ? new Dictionary<string, Entry>() : new Dictionary<string, Entry>(before);
        var list = lines.ToList();
        var keys = list.Select(l => l.Key).ToHashSet();
        var changed = false;

        foreach (var stale in entries.Keys.Where(k => !keys.Contains(k)).ToList())
        {
            entries.Remove(stale);
            changed = true;
        }
        var stamp = TruncateToSeconds(seenAt);
        foreach (var (key, line) in list)
        {
            if (entries.ContainsKey(key)) continue;
            entries[key] = new Entry(line, stamp);
            changed = true;
        }

        if (entries.Count == 0) return Notes.Remove(id);
        Notes[id] = entries;
        return changed;
    }

    public bool Remove(Guid noteId) => Notes.Remove(Models.Note.FormatId(noteId));

    /// <summary>
    /// Folds in a copy of the log made by a sync conflict, keeping the earliest first-seen date of each line.
    /// </summary>
    public void Merge(AgendaLog other)
    {
        foreach (var (id, entries) in other.Notes)
        {
            if (!Notes.TryGetValue(id, out var mine))
            {
                Notes[id] = new Dictionary<string, Entry>(entries);
                continue;
            }
            foreach (var (key, entry) in entries)
            {
                if (!mine.TryGetValue(key, out var existing) || entry.FirstSeen < existing.FirstSeen)
                    mine[key] = entry;
            }
        }
    }

    // The Mac app decodes dates with Swift's .iso8601 strategy, which rejects fractional seconds
    private static DateTimeOffset TruncateToSeconds(DateTimeOffset date) =>
        new(date.UtcDateTime.Ticks - date.UtcDateTime.Ticks % TimeSpan.TicksPerSecond, TimeSpan.Zero);

    private sealed class SecondsDateConverter : JsonConverter<DateTimeOffset>
    {
        public override DateTimeOffset Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) =>
            Models.NoteFormat.ParseDate(reader.GetString() ?? "") ?? throw new JsonException("Invalid date");

        public override void Write(Utf8JsonWriter writer, DateTimeOffset value, JsonSerializerOptions options) =>
            writer.WriteStringValue(value.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture));
    }

    private sealed class OptionalSecondsDateConverter : JsonConverter<DateTimeOffset?>
    {
        public override DateTimeOffset? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) =>
            reader.TokenType == JsonTokenType.Null ? null : Models.NoteFormat.ParseDate(reader.GetString() ?? "");

        public override void Write(Utf8JsonWriter writer, DateTimeOffset? value, JsonSerializerOptions options)
        {
            if (value is { } date)
                writer.WriteStringValue(date.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture));
            else
                writer.WriteNullValue();
        }
    }
}
