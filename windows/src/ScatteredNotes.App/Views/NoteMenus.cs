using System.Diagnostics;
using Avalonia.Controls;
using FluentIcons.Common;
using ScatteredNotes.Core.Models;

namespace ScatteredNotes.App.Views;

/// <summary>Menus shared by the note list and the editor toolbar.</summary>
internal static class NoteMenus
{
    public static ContextMenu ContextMenu(AppState state, Note note, Window? owner)
    {
        var menu = new ContextMenu();
        var pin = new MenuItem { Header = note.IsPinned ? "Unpin Note" : "Pin Note", Icon = Ui.Icon(note.IsPinned ? Symbol.PinOff : Symbol.Pin) };
        pin.Click += (_, _) => state.Store.TogglePin(note);
        menu.Items.Add(pin);
        menu.Items.Add(new Separator());

        var move = new MenuItem { Header = "Move to" };
        foreach (var item in MoveItems(state, note)) move.Items.Add(item);
        menu.Items.Add(move);

        if (note.FilePath is { } path)
        {
            var reveal = new MenuItem { Header = OperatingSystem.IsWindows() ? "Show in File Explorer" : "Reveal in Finder", Icon = Ui.Icon(Symbol.FolderOpen) };
            reveal.Click += (_, _) => RevealFile(path);
            menu.Items.Add(reveal);
        }
        menu.Items.Add(new Separator());

        var delete = new MenuItem { Header = "Delete Note…", Icon = Ui.Icon(Symbol.Delete) };
        delete.Click += async (_, _) => await ConfirmDeleteAsync(state, note, owner);
        menu.Items.Add(delete);
        return menu;
    }

    /// <summary>Inbox, then each project and area, for "Move to" menus.</summary>
    public static List<Control> MoveItems(AppState state, Note note)
    {
        var items = new List<Control>();
        MenuItem Item(string header, string icon, CategoryType type, string? target)
        {
            var isCurrent = note.CategoryType == type && (type == CategoryType.Inbox || note.TargetName == target);
            var item = new MenuItem
            {
                Header = header,
                Icon = Ui.Icon(Ui.SymbolFor(icon), 16, Ui.DestinationBrush(type)),
                ToggleType = MenuItemToggleType.Radio,
                IsChecked = isCurrent,
            };
            item.Click += (_, _) => state.Store.Move(note, type, target);
            return item;
        }

        items.Add(Item("Inbox", "tray.fill", CategoryType.Inbox, null));
        if (state.Store.Projects.Count > 0)
        {
            items.Add(new Separator());
            items.AddRange(state.Store.Projects.Select(p => Item(p.Name, p.IconName, CategoryType.Project, p.Name)));
        }
        if (state.Store.Areas.Count > 0)
        {
            items.Add(new Separator());
            items.AddRange(state.Store.Areas.Select(a => Item(a.Name, a.IconName, CategoryType.Area, a.Name)));
        }
        return items;
    }

    public static async Task ConfirmDeleteAsync(AppState state, Note note, Window? owner)
    {
        if (owner is null) return;
        var confirmed = await Dialogs.ConfirmAsync(owner, "Delete Note?",
            $"Are you sure you want to delete \"{note.DisplayTitle}\"? This will remove the file from disk.", "Delete");
        if (!confirmed) return;
        if (state.SelectedNote?.Id == note.Id) state.SelectNote(null);
        state.Store.Delete(note);
    }

    public static void RevealFile(string path)
    {
        if (OperatingSystem.IsWindows())
            Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{path}\"") { UseShellExecute = false });
        else if (OperatingSystem.IsMacOS())
            Process.Start("open", ["-R", path]);
    }
}
