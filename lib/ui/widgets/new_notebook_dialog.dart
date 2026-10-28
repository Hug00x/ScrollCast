import 'package:flutter/material.dart';
import '../../models/notebook_model.dart';
import 'notebook_paper.dart';

class NotebookDraft {
  const NotebookDraft({
    required this.name,
    required this.folder,
    required this.paperStyle,
  });

  final String name;
  final String? folder;
  final NotebookPaperStyle paperStyle;
}

class NewNotebookDialog extends StatefulWidget {
  const NewNotebookDialog({super.key, this.initialFolder});

  final String? initialFolder;

  @override
  State<NewNotebookDialog> createState() => _NewNotebookDialogState();
}

class _NewNotebookDialogState extends State<NewNotebookDialog> {
  final _name = TextEditingController();
  late final _folder = TextEditingController(text: widget.initialFolder ?? '');
  NotebookPaperStyle _paperStyle = NotebookPaperStyle.plain;

  @override
  void dispose() {
    _name.dispose();
    _folder.dispose();
    super.dispose();
  }

  void _create() {
    final name = _name.text.trim();
    final folder = _folder.text.trim();
    Navigator.of(context).pop(
      NotebookDraft(
        name: name.isEmpty ? 'Caderno' : name,
        folder: folder.isEmpty ? null : folder,
        paperStyle: _paperStyle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Novo caderno'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nome'),
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _folder,
              decoration: const InputDecoration(labelText: 'Pasta (opcional)'),
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 24),
            Text('Tipo de papel', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final style in NotebookPaperStyle.values)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: style == NotebookPaperStyle.grid ? 0 : 8,
                      ),
                      child: _PaperOption(
                        style: style,
                        selected: _paperStyle == style,
                        onTap: () => setState(() => _paperStyle = style),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Este papel será usado em todas as páginas do caderno.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _create, child: const Text('Criar')),
      ],
    );
  }
}

class _PaperOption extends StatelessWidget {
  const _PaperOption({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final NotebookPaperStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = switch (style) {
      NotebookPaperStyle.plain => 'Liso',
      NotebookPaperStyle.lined => 'Com linhas',
      NotebookPaperStyle.grid => 'Quadriculado',
    };
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                ExcludeSemantics(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: SizedBox(
                      height: 100,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          NotebookPaper(style: style, spacing: 12),
                          if (selected)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Icon(
                                Icons.check_circle,
                                color: theme.colorScheme.primary,
                                size: 20,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 32),
                  child: Center(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
