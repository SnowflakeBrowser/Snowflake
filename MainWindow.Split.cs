using System.Windows;
using System.Windows.Controls;

namespace Veil;

/// Split view: two tabs side by side. Click a pane to work in it.
public sealed partial class MainWindow
{
    BrowserTab splitLeft, splitRight;
    readonly Border splitDivider = new Border { Width = 6, Visibility = Visibility.Collapsed };

    bool IsSplit => splitLeft != null && splitRight != null && tabs.Contains(splitLeft) && tabs.Contains(splitRight);

    void InitSplitLayout()
    {
        content.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        content.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        content.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        splitDivider.SetResourceReference(Border.BackgroundProperty, "Bar");
        Grid.SetColumn(splitDivider, 1);
        content.Children.Add(splitDivider);
    }

    /// Which tabs are on screen when `shown` is the active tab.
    bool PaneVisible(BrowserTab x, BrowserTab shown) =>
        x == shown || (IsSplit && (x == splitLeft || x == splitRight));

    void LayoutPanes()
    {
        bool split = IsSplit;
        foreach (var x in tabs)
        {
            if (x.Host == null) continue;
            if (split && x == splitLeft) { Grid.SetColumn(x.Host, 0); Grid.SetColumnSpan(x.Host, 1); }
            else if (split && x == splitRight) { Grid.SetColumn(x.Host, 2); Grid.SetColumnSpan(x.Host, 1); }
            else { Grid.SetColumn(x.Host, 0); Grid.SetColumnSpan(x.Host, 3); }
        }
        splitDivider.Visibility = split ? Visibility.Visible : Visibility.Collapsed;
    }

    void ToggleSplit()
    {
        if (IsSplit) { CloseSplit(); return; }
        if (active == null) return;
        var left = active;
        var right = NewTab(null, left.IsPrivate, false);
        splitLeft = left;
        splitRight = right;
        Activate(right);
    }

    void CloseSplit()
    {
        splitLeft = null;
        splitRight = null;
        foreach (var x in tabs) { if (x.Host != null) x.Host.Visibility = x == active ? Visibility.Visible : Visibility.Collapsed; }
        LayoutPanes();
    }

    /// Called when the page in a pane gets keyboard focus.
    public void PaneFocused(BrowserTab t)
    {
        if (!IsSplit || t == active || (t != splitLeft && t != splitRight)) return;
        active = t;
        foreach (var x in tabs) StyleHeader(x);
        UpdateChrome(true);
    }
}
