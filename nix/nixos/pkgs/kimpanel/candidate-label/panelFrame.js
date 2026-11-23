import Clutter from 'gi://Clutter';
import GObject from 'gi://GObject';
import Graphene from 'gi://Graphene';
import St from 'gi://St';

export const PanelFrame = GObject.registerClass(class KimpanelPanelFrame extends St.Bin {
    vfunc_paint_node(node, context) {
        const views = this.peek_stage_views();
        const scale = views.length === 1 ? views[0].get_scale() : 1;
        const [width, height] = this.get_size();
        if (Number.isInteger(scale) || width <= 0 || height <= 0)
            return super.vfunc_paint_node(node, context);

        const [x, y] = this.get_transformed_position();
        const monitor = views[0].layout;
        const px = (x - monitor.x) * scale;
        const py = (y - monitor.y) * scale;
        const theme = this.get_theme_node();
        // Split the rounding error between the inner and outer edges. This
        // gives both opposing sides the same coverage even at 1.5 pixels.
        const inset = side => {
            const stroke = theme.get_border_width(side) * scale;
            return (Math.round(stroke) - stroke) / 2;
        };
        const left = Math.round(px) + inset(St.Side.LEFT);
        const top = Math.round(py) + inset(St.Side.TOP);
        const right = Math.round(px + width * scale) - inset(St.Side.RIGHT);
        const bottom = Math.round(py + height * scale) - inset(St.Side.BOTTOM);

        // Snap both ends of the CSS box. St paints its straight borders as
        // rectangles; children are painted separately with their own transforms.
        const matrix = new Graphene.Matrix().init_scale(
            (right - left) / (width * scale), (bottom - top) / (height * scale), 1);
        matrix.translate(new Graphene.Point3D({
            x: (left - px) / scale,
            y: (top - py) / scale,
        }));
        const frame = Clutter.TransformNode.new(matrix);
        node.add_child(frame);
        super.vfunc_paint_node(frame, context);
    }
});
