import 'package:flutter/material.dart';

import '../data/app_db.dart';
import 'theme.dart';

Future<int?> pickNotebookColor(BuildContext context, {required int initial}) =>
    showDialog<int>(
      context: context,
      builder: (_) => _NotebookColorPicker(initial: initial),
    );

String _hexOf(Color color) => (color.toARGB32() & 0xFFFFFF)
    .toRadixString(16)
    .padLeft(6, '0')
    .toUpperCase();

class _NotebookColorPicker extends StatefulWidget {
  const _NotebookColorPicker({required this.initial});

  final int initial;

  @override
  State<_NotebookColorPicker> createState() => _NotebookColorPickerState();
}

class _NotebookColorPickerState extends State<_NotebookColorPicker> {
  late HSVColor _hsv;
  late Color _color;
  late final TextEditingController _hexController;
  bool _hexError = false;

  @override
  void initState() {
    super.initState();
    _color = Color(widget.initial);
    _hsv = HSVColor.fromColor(_color);
    _hexController = TextEditingController(text: _hexOf(_color));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _applyColor(Color color, {bool rewriteHex = true}) {
    setState(() {
      _color = color;
      _hsv = HSVColor.fromColor(color);
      _hexError = false;
      if (rewriteHex) {
        _hexController.text = _hexOf(color);
      }
    });
  }

  void _hsvChanged(HSVColor hsv) {
    _applyColor(hsv.toColor());
  }

  void _hexChanged(String raw) {
    var text = raw.trim();
    if (text.startsWith('#')) {
      text = text.substring(1);
    }
    final valid = RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(text);
    if (valid) {
      _applyColor(Color(0xFF000000 | int.parse(text, radix: 16)),
          rewriteHex: false);
    } else {
      setState(() => _hexError = raw.trim().isNotEmpty);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    return AlertDialog(
      title: const Text('自定义背景色'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: spaceSm,
              runSpacing: spaceSm,
              children: [
                for (final value in notebookPalette)
                  _PaletteSwatch(
                    color: Color(value),
                    selected: _color.toARGB32() == value,
                    onTap: () => _applyColor(Color(value)),
                  ),
              ],
            ),
            const SizedBox(height: spaceMd),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _color,
                    borderRadius: BorderRadius.circular(radiusSm),
                    border: Border.all(color: t.hairline),
                  ),
                ),
                const SizedBox(width: spaceSm),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: t.surfaceAlt,
                      borderRadius: BorderRadius.circular(radiusMd),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 3,
                          height: 20,
                          margin: const EdgeInsets.only(right: 9),
                          decoration: BoxDecoration(
                            color: _color,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                              color: _color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '笔记本预览',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: t.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: spaceSm),
            _sliderRow('色相', _hsv.hue, 360, 360,
                (v) => _hsvChanged(_hsv.withHue(v))),
            _sliderRow('饱和', _hsv.saturation, 1, 100,
                (v) => _hsvChanged(_hsv.withSaturation(v))),
            _sliderRow('明度', _hsv.value, 1, 100,
                (v) => _hsvChanged(_hsv.withValue(v))),
            const SizedBox(height: spaceSm),
            TextField(
              controller: _hexController,
              onChanged: _hexChanged,
              decoration: InputDecoration(
                labelText: 'Hex',
                prefixText: '# ',
                errorText: _hexError ? '6 位十六进制颜色' : null,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _hexError
              ? null
              : () => Navigator.of(context).pop(_color.toARGB32()),
          child: const Text('确定'),
        ),
      ],
    );
  }

  Widget _sliderRow(String label, double value, double max, int divisions,
      ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(
          width: 36,
          child: Text(label, style: Theme.of(context).textTheme.labelSmall),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(0, max),
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _PaletteSwatch extends StatelessWidget {
  const _PaletteSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    return InkWell(
      borderRadius: BorderRadius.circular(radiusSm),
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radiusSm),
          border: Border.all(
            color: selected ? t.ink : t.hairline,
            width: selected ? 2 : 1,
          ),
        ),
        child: selected
            ? Icon(
                Icons.check,
                size: 16,
                color: ThemeData.estimateBrightnessForColor(color) ==
                        Brightness.dark
                    ? Colors.white
                    : Colors.black,
              )
            : null,
      ),
    );
  }
}