/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2026 elementary, Inc. (https://elementary.io)
 */

public enum Code.PaneType {
    EDITOR,
    TERMINAL
}

public class Code.PaneEntry : Gtk.Box {
    public signal void pane_focus_in ();
    public Gtk.Widget content { get; private set; }
    public PaneType pane_type { get; private set; }

    public PaneEntry (Gtk.Widget content, PaneType type) {
        Object (
            orientation: Gtk.Orientation.VERTICAL,
            hexpand: true,
            vexpand: true
        );

        this.content = content;
        this.pane_type = type;
        pack_start (content, true, true, 0);
        show_all ();
    }

    public override void set_focus_child (Gtk.Widget? child) {
        base.set_focus_child (child);
        if (child != null) {
            pane_focus_in ();
        }
    }
}

public class Code.SplitView : Gtk.Box {
    public signal void active_pane_changed (PaneEntry pane);
    public signal void pane_added (PaneEntry pane);
    public signal void pane_removed (PaneEntry pane);

    private PaneEntry? _active_pane = null;
    public PaneEntry? active_pane {
        get { return _active_pane; }
    }

    private Gee.ArrayList<PaneEntry> panes;
    private Gtk.Widget root_content;
    private unowned Scratch.MainWindow window;

    public int pane_count {
        get { return panes.size; }
    }

    public SplitView (Scratch.MainWindow window) {
        Object (
            orientation: Gtk.Orientation.VERTICAL,
            hexpand: true,
            vexpand: true
        );

        this.window = window;
        panes = new Gee.ArrayList<PaneEntry> ();
    }

    public void set_initial_content (Gtk.Widget content, PaneType type) {
        var pane = new PaneEntry (content, type);
        panes.add (pane);
        pane.pane_focus_in.connect (() => set_active (pane));
        root_content = pane;
        pack_start (pane, true, true, 0);
        _active_pane = pane;
    }

    public void set_active (PaneEntry pane) {
        if (_active_pane == pane) {
            return;
        }

        if (_active_pane != null) {
            _active_pane.get_style_context ().remove_class ("active-pane");
        }

        _active_pane = pane;

        if (_active_pane != null) {
            _active_pane.get_style_context ().add_class ("active-pane");
            active_pane_changed (_active_pane);
        }
    }

    public PaneEntry? split_right (PaneType type) {
        return do_split (Gtk.Orientation.HORIZONTAL, type);
    }

    public PaneEntry? split_down (PaneType type) {
        return do_split (Gtk.Orientation.VERTICAL, type);
    }

    private PaneEntry? do_split (Gtk.Orientation orientation, PaneType new_type) {
        if (_active_pane == null || panes.size >= 4) {
            return null;
        }

        var current_pane = _active_pane;
        var parent = current_pane.get_parent ();

        Gtk.Widget new_content;
        if (new_type == PaneType.TERMINAL) {
            new_content = new Code.Terminal () {
                visible = true
            };
        } else {
            new_content = new Scratch.Widgets.DocumentView (window);
        }

        var new_pane = new PaneEntry (new_content, new_type);
        panes.add (new_pane);
        new_pane.pane_focus_in.connect (() => set_active (new_pane));

        var paned = new Gtk.Paned (orientation) {
            hexpand = true,
            vexpand = true,
            wide_handle = true
        };

        if (parent == this) {
            remove (current_pane);
            paned.pack1 (current_pane, true, false);
            paned.pack2 (new_pane, true, false);
            root_content = paned;
            pack_start (paned, true, true, 0);
        } else if (parent is Gtk.Paned) {
            var pp = (Gtk.Paned) parent;
            bool is_child1 = (pp.get_child1 () == current_pane);
            pp.remove (current_pane);

            paned.pack1 (current_pane, true, false);
            paned.pack2 (new_pane, true, false);

            if (is_child1) {
                pp.pack1 (paned, true, false);
            } else {
                pp.pack2 (paned, true, false);
            }
        }

        paned.show_all ();

        // Set 50/50 split after widget gets its allocation
        Idle.add (() => {
            int size;
            if (orientation == Gtk.Orientation.HORIZONTAL) {
                size = paned.get_allocated_width ();
            } else {
                size = paned.get_allocated_height ();
            }

            if (size > 0) {
                paned.position = size / 2;
            }

            return Source.REMOVE;
        });

        pane_added (new_pane);
        set_active (new_pane);

        // Focus the new content
        new_pane.content.grab_focus ();
        return new_pane;
    }

    public bool close_pane (PaneEntry? target = null) {
        var pane_to_close = target ?? _active_pane;

        if (panes.size <= 1 || pane_to_close == null) {
            return false;
        }

        var parent = pane_to_close.get_parent ();
        if (!(parent is Gtk.Paned)) {
            return false;
        }

        var parent_paned = (Gtk.Paned) parent;
        Gtk.Widget sibling;
        if (parent_paned.get_child1 () == pane_to_close) {
            sibling = parent_paned.get_child2 ();
        } else {
            sibling = parent_paned.get_child1 ();
        }

        var grandparent = parent_paned.get_parent ();

        parent_paned.remove (pane_to_close);
        parent_paned.remove (sibling);

        if (grandparent == this) {
            remove (parent_paned);
            root_content = sibling;
            pack_start (sibling, true, true, 0);
        } else if (grandparent is Gtk.Paned) {
            var gp = (Gtk.Paned) grandparent;
            bool is_child1 = (gp.get_child1 () == parent_paned);
            gp.remove (parent_paned);
            if (is_child1) {
                gp.pack1 (sibling, true, false);
            } else {
                gp.pack2 (sibling, true, false);
            }
        }

        panes.remove (pane_to_close);
        pane_removed (pane_to_close);
        pane_to_close.destroy ();

        // Focus the first remaining pane
        if (panes.size > 0) {
            set_active (panes[0]);
            panes[0].content.grab_focus ();
        }

        show_all ();
        return true;
    }

    public void focus_direction (Gtk.DirectionType direction) {
        if (_active_pane == null || panes.size <= 1) {
            return;
        }

        int active_x, active_y;
        _active_pane.translate_coordinates (
            this,
            _active_pane.get_allocated_width () / 2,
            _active_pane.get_allocated_height () / 2,
            out active_x, out active_y
        );

        PaneEntry? best = null;
        int best_distance = int.MAX;

        foreach (var pane in panes) {
            if (pane == _active_pane) {
                continue;
            }

            int px, py;
            pane.translate_coordinates (
                this,
                pane.get_allocated_width () / 2,
                pane.get_allocated_height () / 2,
                out px, out py
            );

            bool valid = false;
            switch (direction) {
                case Gtk.DirectionType.LEFT:
                case Gtk.DirectionType.TAB_BACKWARD:
                    valid = px < active_x;
                    break;
                case Gtk.DirectionType.RIGHT:
                case Gtk.DirectionType.TAB_FORWARD:
                    valid = px > active_x;
                    break;
                case Gtk.DirectionType.UP:
                    valid = py < active_y;
                    break;
                case Gtk.DirectionType.DOWN:
                    valid = py > active_y;
                    break;
            }

            if (valid) {
                int dist = (px - active_x).abs () + (py - active_y).abs ();
                if (dist < best_distance) {
                    best_distance = dist;
                    best = pane;
                }
            }
        }

        if (best != null) {
            set_active (best);
            best.content.grab_focus ();
        }
    }

    public PaneEntry? find_pane_for_widget (Gtk.Widget widget) {
        foreach (var pane in panes) {
            if (pane.content == widget) {
                return pane;
            }
        }

        return null;
    }

    public Gee.List<Scratch.Widgets.DocumentView> get_all_document_views () {
        var views = new Gee.ArrayList<Scratch.Widgets.DocumentView> ();
        foreach (var pane in panes) {
            if (pane.pane_type == PaneType.EDITOR && pane.content is Scratch.Widgets.DocumentView) {
                views.add ((Scratch.Widgets.DocumentView) pane.content);
            }
        }

        return views;
    }

    public Gee.List<PaneEntry> get_panes () {
        return panes.read_only_view;
    }
}
