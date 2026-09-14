import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';

/// Amostras rápidas (a primeira é a cor original do app).
const colorSwatches = [
  0xFF7C4DFF, 0xFF2196F3, 0xFF00BFA5, 0xFF4CAF50, 0xFFFFC107, //
  0xFFFF5722, 0xFFE91E63, 0xFF9E9E9E, 0xFF00E676, 0xFFB5651D,
];

/// Escolha livre de cor: matiz, saturação, brilho, código hex e amostras.
Future<Color?> showColorPicker(BuildContext context, {required Color initial, String? title}) =>
    showDialog<Color>(context: context, builder: (_) => _ColorPickerDialog(initial: initial, title: title));

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.initial, this.title});
  final Color initial;
  final String? title;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial.withValues(alpha: 1));
  late final _hex = TextEditingController(text: _hexOf(_hsv.toColor()));

  static String _hexOf(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  void _set(HSVColor v, {bool fromHex = false}) {
    setState(() => _hsv = v);
    if (!fromHex) _hex.text = _hexOf(v.toColor());
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final color = _hsv.toColor();
    return AlertDialog(
      title: Text(widget.title ?? l10n.pickColor),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 56,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                ),
              ),
              const SizedBox(height: 12),
              _GradientSlider(
                label: l10n.hue,
                value: _hsv.hue / 360,
                colors: [for (var h = 0; h <= 360; h += 30) HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor()],
                onChanged: (v) => _set(_hsv.withHue(v * 360)),
              ),
              _GradientSlider(
                label: l10n.saturation,
                value: _hsv.saturation,
                colors: [_hsv.withSaturation(0).toColor(), _hsv.withSaturation(1).toColor()],
                onChanged: (v) => _set(_hsv.withSaturation(v)),
              ),
              _GradientSlider(
                label: l10n.brightness,
                value: _hsv.value,
                colors: [Colors.black, _hsv.withValue(1).toColor()],
                onChanged: (v) => _set(_hsv.withValue(v)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _hex,
                decoration: InputDecoration(labelText: l10n.colorHex, isDense: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')), LengthLimitingTextInputFormatter(7)],
                onChanged: (t) {
                  final h = t.replaceAll('#', '');
                  if (h.length == 6) {
                    final v = int.tryParse(h, radix: 16);
                    if (v != null) _set(HSVColor.fromColor(Color(0xFF000000 | v)), fromHex: true);
                  }
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in colorSwatches)
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _set(HSVColor.fromColor(Color(c))),
                      child: CircleAvatar(radius: 14, backgroundColor: Color(c)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(onPressed: () => Navigator.pop(context, color), child: Text(l10n.useThis)),
      ],
    );
  }
}

/// Slider com o gradiente da grandeza como trilho.
class _GradientSlider extends StatelessWidget {
  const _GradientSlider({required this.label, required this.value, required this.colors, required this.onChanged});
  final String label;
  final double value;
  final List<Color> colors;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 8), child: Text(label, style: Theme.of(context).textTheme.labelMedium)),
        SizedBox(
          height: 32,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                height: 12,
                margin: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), gradient: LinearGradient(colors: colors)),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                  thumbColor: Colors.white,
                ),
                child: Slider(value: value.clamp(0, 1), onChanged: onChanged),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
