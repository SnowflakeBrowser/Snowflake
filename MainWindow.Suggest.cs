using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using Veil.Core;

namespace Veil;

/// Address bar suggestions: a list under the address bar while you type (search, sites, bookmarks, history).
public sealed partial class MainWindow
{
    Border addressBox;
    Popup suggestPopup;
    Border suggestCard;
    StackPanel suggestRows;
    readonly List<Suggestion> suggestItems = new();
    readonly List<Border> suggestViews = new();
    Brush suggestSelBrush;
    int suggestSel;
    List<string> suggestHosts = new();
    bool suggestStale = true;
    static readonly FontFamily SuggestFont = new FontFamily("Segoe UI Variable Text, Segoe UI, Arial");

    void InitSuggestions()
    {
        suggestRows = new StackPanel();
        suggestCard = new Border
        {
            CornerRadius = new CornerRadius(12), BorderThickness = new Thickness(1), Padding = new Thickness(6),
            Margin = new Thickness(12, 4, 12, 14), Child = suggestRows,
            Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 16, ShadowDepth = 3, Direction = 270, Opacity = 0.4, Color = Colors.Black },
        };
        suggestCard.SetResourceReference(Border.BackgroundProperty, "Field");
        suggestCard.SetResourceReference(Border.BorderBrushProperty, "Line");
        suggestPopup = new Popup
        {
            AllowsTransparency = true, StaysOpen = true, Placement = PlacementMode.Bottom, PlacementTarget = addressBox,
            PopupAnimation = PopupAnimation.None, Child = suggestCard,
        };
        address.TextChanged += (s, e) => OnAddressTextChanged();
        address.PreviewKeyDown += OnAddressKey;
        address.GotKeyboardFocus += (s, e) => suggestStale = true;
        address.LostKeyboardFocus += (s, e) => HideSuggestions();
        Deactivated += (s, e) => HideSuggestions();
    }

    void HideSuggestions()
    {
        if (suggestPopup != null) suggestPopup.IsOpen = false;
    }

    void OnAddressTextChanged()
    {
        if (suggestPopup == null || !address.IsKeyboardFocusWithin) return;
        var query = address.Text.Trim();
        var S = Services.Settings;
        if (query.Length == 0 || !S.Bool("suggestionsEnabled")) { HideSuggestions(); return; }
        bool fromHistory = S.Bool("suggestFromHistory");
        if (fromHistory && suggestStale) { suggestHosts = Services.History.TopHosts(); suggestStale = false; }
        var items = Suggestions.Build(
            query,
            fromHistory ? Services.History.Search(query, 60) : new List<HistoryEntry>(),
            fromHistory ? Services.Bookmarks.All : new List<Bookmark>(),
            fromHistory ? suggestHosts : new List<string>(),
            S.Bool("suggestPopularSites"));
        if (items.Count == 0) { HideSuggestions(); return; }
        ShowSuggestions(items);
    }

    void ShowSuggestions(List<Suggestion> items)
    {
        suggestItems.Clear();
        suggestItems.AddRange(items);
        suggestSel = 0;
        suggestCard.Width = Math.Max(260, addressBox.ActualWidth);
        suggestPopup.HorizontalOffset = -12;
        suggestPopup.VerticalOffset = 0;
        var ac = ((SolidColorBrush)FindResource("Accent")).Color;
        suggestSelBrush = new SolidColorBrush(Color.FromArgb(0x38, ac.R, ac.G, ac.B));

        suggestRows.Children.Clear();
        suggestViews.Clear();
        for (int i = 0; i < suggestItems.Count; i++)
        {
            var sg = suggestItems[i];
            int idx = i;
            string glyph = sg.Kind == SuggestionKind.Search ? "\uE721" : sg.Kind == SuggestionKind.Bookmark ? "\uE734" : sg.Kind == SuggestionKind.History ? "\uE81C" : "\uE774";
            var icon = new TextBlock { Text = glyph, FontFamily = IconFont, FontSize = 14, Width = 24, VerticalAlignment = VerticalAlignment.Center };
            icon.SetResourceReference(TextBlock.ForegroundProperty, "Mute");
            var title = new TextBlock { Text = sg.Title, FontFamily = SuggestFont, FontSize = 13, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center };
            title.SetResourceReference(TextBlock.ForegroundProperty, "Text");
            var detail = new TextBlock { Text = sg.Detail, FontFamily = SuggestFont, FontSize = 12, Margin = new Thickness(12, 0, 0, 0), MaxWidth = 280, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center };
            detail.SetResourceReference(TextBlock.ForegroundProperty, "Mute");
            var dock = new DockPanel { LastChildFill = true };
            DockPanel.SetDock(icon, Dock.Left);
            DockPanel.SetDock(detail, Dock.Right);
            dock.Children.Add(icon);
            dock.Children.Add(detail);
            dock.Children.Add(title);
            var row = new Border { Height = 34, CornerRadius = new CornerRadius(8), Padding = new Thickness(8, 0, 10, 0), Background = Brushes.Transparent, Child = dock, Cursor = Cursors.Hand };
            row.MouseEnter += (_, __) => SetSuggestionSelection(idx);
            row.MouseLeftButtonUp += (_, __) => ChooseSuggestion(sg);
            suggestViews.Add(row);
            suggestRows.Children.Add(row);
        }
        SetSuggestionSelection(0);
        suggestPopup.IsOpen = true;
    }

    void SetSuggestionSelection(int index)
    {
        suggestSel = Math.Max(0, Math.Min(suggestViews.Count - 1, index));
        for (int i = 0; i < suggestViews.Count; i++)
            suggestViews[i].Background = i == suggestSel ? suggestSelBrush : Brushes.Transparent;
    }

    void OnAddressKey(object sender, KeyEventArgs e)
    {
        if (suggestPopup == null || !suggestPopup.IsOpen) return;
        if (e.Key == Key.Down) { SetSuggestionSelection(suggestSel + 1); e.Handled = true; }
        else if (e.Key == Key.Up) { SetSuggestionSelection(suggestSel - 1); e.Handled = true; }
        else if (e.Key == Key.Enter && suggestSel > 0 && suggestSel < suggestItems.Count) { ChooseSuggestion(suggestItems[suggestSel]); e.Handled = true; }
        else if (e.Key == Key.Escape) HideSuggestions();
    }

    void ChooseSuggestion(Suggestion s)
    {
        HideSuggestions();
        var template = SearchEngines.Template(Services.Settings.Str("searchEngine"));
        string url = s.Kind == SuggestionKind.Search ? template.Replace("%s", Uri.EscapeDataString(s.Target)) : s.Target;
        if (active == null) return;
        active.Navigate(url);
        address.Text = UrlResolver.Display(url);
        active.FocusPage();
    }
}
