import 'package:flutter/material.dart';

/// Lista reordenável com liga/desliga (abas, botões do player, seções do
/// Início). [min]/[max] limitam quantos ficam ligados; [onLimit] avisa quando
/// o toque passaria do limite.
class OrderedToggles extends StatelessWidget {
  const OrderedToggles({
    super.key,
    required this.all,
    required this.enabled,
    required this.names,
    required this.onChanged,
    this.icons = const {},
    this.min = 0,
    this.max,
    this.onLimit,
  });

  final List<String> all;
  final List<String> enabled;
  final Map<String, String> names;
  final Map<String, IconData> icons;
  final ValueChanged<List<String>> onChanged;
  final int min;
  final int? max;
  final VoidCallback? onLimit;

  @override
  Widget build(BuildContext context) {
    // Ligados primeiro (na ordem escolhida), depois os desligados.
    final items = [...enabled, ...all.where((k) => !enabled.contains(k))];
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorder: (from, to) {
        final list = List.of(items);
        final item = list.removeAt(from);
        list.insert(to > from ? to - 1 : to, item);
        onChanged(list.where(enabled.contains).toList());
      },
      children: [
        for (var i = 0; i < items.length; i++)
          CheckboxListTile(
            key: ValueKey(items[i]),
            value: enabled.contains(items[i]),
            title: Row(
              children: [
                if (icons[items[i]] != null) ...[Icon(icons[items[i]], size: 20), const SizedBox(width: 12)],
                Flexible(child: Text(names[items[i]] ?? items[i])),
              ],
            ),
            secondary: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (v) {
              final on = v == true;
              if ((on && max != null && enabled.length >= max!) || (!on && enabled.length <= min)) {
                onLimit?.call();
                return;
              }
              final next = on ? [...enabled, items[i]] : enabled.where((k) => k != items[i]).toList();
              // Mantém a ordem da lista visível.
              onChanged(items.where(next.contains).toList());
            },
          ),
      ],
    );
  }
}
