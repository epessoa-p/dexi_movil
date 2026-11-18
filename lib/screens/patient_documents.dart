import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/models.dart';
import '../ui/common.dart';

/// Documentos y fotos del paciente: radiografías, fotos intraorales,
/// consentimientos… Se toman con la cámara o se eligen de la galería. Son
/// privados: se cargan con el token de la sesión.
class PatientDocuments extends StatefulWidget {
  const PatientDocuments({super.key, required this.patientId, this.canUpload = false});

  final int patientId;
  final bool canUpload;

  @override
  State<PatientDocuments> createState() => _PatientDocumentsState();
}

class _PatientDocumentsState extends State<PatientDocuments> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();
  bool _uploading = false;

  Future<void> _add(List<Map<String, dynamic>> categories) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    // Reducida en el teléfono: una foto clínica no necesita 12 MP.
    final photo = await ImagePicker().pickImage(source: source, maxWidth: 2200, imageQuality: 85);
    if (photo == null || !mounted) return;

    final category = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('¿Qué es?', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final c in categories) ListTile(title: Text(c.str('label') ?? ''), onTap: () => Navigator.pop(context, c.str('key'))),
          ],
        ),
      ),
    );
    if (category == null || !mounted) return;

    setState(() => _uploading = true);
    showInfo(context, 'Subiendo la foto…');
    try {
      final bytes = await photo.readAsBytes();
      if (!mounted) return;
      await context.session.api.upload('/patients/${widget.patientId}/documents', 'file', bytes, photo.name, fields: {'category': category});
      if (!mounted) return;
      showDone(context, 'Foto guardada en la ficha.');
      _loader.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.session.api;

    return Loader<Map<String, dynamic>>(
      key: _loader,
      load: () => api.get('/patients/${widget.patientId}/documents'),
      builder: (context, data, reload) {
        final items = data.list('data');
        final categories = data.list('categories');
        return Stack(
          children: [
            if (items.isEmpty)
              ListView(
                children: const [
                  EmptyState(
                    icon: Icons.photo_library_outlined,
                    message: 'Sin fotos ni documentos. Toma radiografías o fotos intraorales con la cámara.',
                  ),
                ],
              )
            else
              GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 160),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 180,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: .8,
                ),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final d = items[i];
                  final image = d.flag('is_image');
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: image
                          ? () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    _PhotoScreen(title: d.str('title') ?? '', url: api.url(d.str('file_path')!), headers: api.authHeaders),
                              ),
                            )
                          : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: image
                                ? Image.network(
                                    api.url(d.str('file_path')!),
                                    headers: api.authHeaders,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
                                  )
                                : const Icon(Icons.picture_as_pdf_outlined, size: 48),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  d.str('category_label') ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                Text(fmtShortDate(d.date('taken_on')), style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            if (widget.canUpload)
              Positioned(
                right: 16,
                bottom: 88,
                child: FloatingActionButton.small(
                  heroTag: 'add-photo',
                  tooltip: 'Agregar foto',
                  onPressed: _uploading ? null : () => _add(categories),
                  child: _uploading
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.add_a_photo_outlined),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// La foto a pantalla completa, con zoom.
class _PhotoScreen extends StatelessWidget {
  const _PhotoScreen({required this.title, required this.url, required this.headers});

  final String title;
  final String url;
  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(title)),
      body: InteractiveViewer(
        maxScale: 6,
        child: Center(child: Image.network(url, headers: headers)),
      ),
    );
  }
}
