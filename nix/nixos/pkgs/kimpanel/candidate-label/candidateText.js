import Clutter from 'gi://Clutter';
import GObject from 'gi://GObject';
import Graphene from 'gi://Graphene';

// St.Label measures its ClutterText before the actor transform is applied.
const TextMetrics = GObject.registerClass(class KimpanelTextMetrics extends Clutter.Constraint {
    vfunc_update_preferred_size(actor, direction, forSize, minimum, natural) {
        return [minimum * actor.scale_x, natural * actor.scale_x];
    }

    vfunc_update_allocation(actor, box) {
        box.set_size(box.get_width() / actor.scale_x, box.get_height() / actor.scale_y);
    }
});

// Place the glyph bitmap on a device pixel even when the popup or its padding
// starts at a fractional pixel. Keep the label's layout and pointer target intact.
const PixelAlign = GObject.registerClass(class KimpanelPixelAlign extends Clutter.Effect {
    vfunc_paint_node(node, context, flags) {
        const text = this.get_actor();
        const [view] = text.peek_stage_views();
        if (!view)
            return super.vfunc_paint_node(node, context, flags);

        const [x, y] = text.get_transformed_position();
        const monitor = view.layout;
        const scale = view.get_scale();
        const px = (x - monitor.x) * scale;
        const py = (y - monitor.y) * scale;
        const matrix = new Graphene.Matrix().init_translate(new Graphene.Point3D({
            x: (Math.round(px) - px) / text.get_resource_scale(),
            y: (Math.round(py) - py) / text.get_resource_scale(),
            z: 0,
        }));
        const aligned = Clutter.TransformNode.new(matrix);
        node.add_child(aligned);
        super.vfunc_paint_node(aligned, context, flags);
    }
});

export function adaptPanelText(label) {
    const text = label.clutter_text;
    const metrics = new TextMetrics({enabled: false});
    const align = new PixelAlign({enabled: false});
    text.add_constraint(metrics);
    text.add_effect(align);
    label.set_offscreen_redirect(Clutter.OffscreenRedirect.AUTOMATIC_FOR_OPACITY);

    function update() {
        if (!label.get_stage())
            return;
        const views = text.peek_stage_views();
        const scale = views.length === 1 ? views[0].get_scale() : 1;
        const zoom = Number.isInteger(scale) ? 1 : text.get_resource_scale() / scale;
        if (zoom === 1 && !metrics.enabled)
            return;

        // Clutter rasterizes at its integer resource scale. Adjust the Pango
        // size before rasterization and cancel the difference in actor space.
        const font = label.get_theme_node().get_font().copy();
        const size = Math.round(font.get_size() / zoom);
        if (font.get_size_is_absolute())
            font.set_absolute_size(size);
        else
            font.set_size(size);
        text.set_font_description(font);
        if (zoom !== text.scale_x) {
            text.set_scale(zoom, zoom);
            metrics.enabled = align.enabled = zoom !== 1;
            text.queue_relayout();
        }
    }

    label.connect_after('style-changed', update);
    text.connect('stage-views-changed', update);
    text.connect('real-resource-scale-changed', update);
}
