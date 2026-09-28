import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../models/enums.dart';
import '../../../../models/looking_for_model.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/looking_for_controller.dart';

/// Owns its [TextEditingController]s so Android back / dismiss cannot dispose
/// them while the sheet widgets are still mounted.
class CreateLookingForSheet extends StatefulWidget {
  const CreateLookingForSheet({
    super.key,
    required this.controller,
    this.existing,
  });

  final LookingForController controller;
  final LookingForModel? existing;

  static Future<bool> show(
    BuildContext context, {
    required LookingForController controller,
    LookingForModel? existing,
  }) async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          CreateLookingForSheet(controller: controller, existing: existing),
    );
    return created == true;
  }

  @override
  State<CreateLookingForSheet> createState() => _CreateLookingForSheetState();
}

class _CreateLookingForSheetState extends State<CreateLookingForSheet> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _sizeCtrl = TextEditingController();
  final _minCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();
  final _picker = ImagePicker();

  ProductCategory _category = ProductCategory.tops;
  Uint8List? _imageBytes;
  String? _existingImageUrl;
  bool _clearedImage = false;
  bool _submitting = false;
  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _nameCtrl.text = existing.title;
      _descCtrl.text = existing.description;
      _sizeCtrl.text = existing.size ?? '';
      _minCtrl.text = existing.budgetMin == 0
          ? ''
          : existing.budgetMin.toStringAsFixed(0);
      _maxCtrl.text = existing.budgetMax == 0
          ? ''
          : existing.budgetMax.toStringAsFixed(0);
      _category = existing.category;
      _existingImageUrl = existing.thumbnailUrl;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _sizeCtrl.dispose();
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        requestFullMetadata: false,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _clearedImage = false;
      });
    } catch (e) {
      if (!mounted) return;
      showThriftSnackBar(
        context,
        'Could not open your gallery. Check Photos permission and try again.',
        isError: true,
      );
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final error = _isEditing
        ? await widget.controller.updatePost(
            postId: widget.existing!.id,
            title: _nameCtrl.text,
            description: _descCtrl.text,
            category: _category,
            budgetMin: double.tryParse(_minCtrl.text) ?? 0,
            budgetMax: double.tryParse(_maxCtrl.text) ?? 0,
            size: _sizeCtrl.text,
            referenceImageBytes: _imageBytes,
            clearReferenceImage: _clearedImage && _imageBytes == null,
          )
        : await widget.controller.createPost(
            title: _nameCtrl.text,
            description: _descCtrl.text,
            category: _category,
            budgetMin: double.tryParse(_minCtrl.text) ?? 0,
            budgetMax: double.tryParse(_maxCtrl.text) ?? 0,
            size: _sizeCtrl.text,
            referenceImageBytes: _imageBytes,
          );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    Navigator.of(context).pop(true);
  }

  bool get _hasPreview =>
      _imageBytes != null ||
      (_existingImageUrl != null && _existingImageUrl!.isNotEmpty);

  DecorationImage? get _previewImage {
    if (_imageBytes != null) {
      return DecorationImage(
        image: MemoryImage(_imageBytes!),
        fit: BoxFit.cover,
      );
    }
    final url = _existingImageUrl;
    if (url != null && url.isNotEmpty) {
      return DecorationImage(image: NetworkImage(url), fit: BoxFit.cover);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        height: MediaQuery.sizeOf(context).height * 0.9,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isEditing ? 'Edit Request' : 'Create Request',
                    style: AppTypography.heading,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Material(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: _submitting ? null : _pickImage,
                      borderRadius: BorderRadius.circular(12),
                      child: Ink(
                        height: 140,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                          image: _previewImage,
                        ),
                        child: !_hasPreview
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.add_photo_alternate_outlined,
                                    size: 40,
                                    color: AppColors.textSecondary,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Add Reference Image (Optional)',
                                    style: AppTypography.caption,
                                  ),
                                ],
                              )
                            : Align(
                                alignment: Alignment.topRight,
                                child: IconButton(
                                  onPressed: () => setState(() {
                                    _imageBytes = null;
                                    _existingImageUrl = null;
                                    _clearedImage = true;
                                  }),
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                  ),
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.black54,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ThriftTextField(
                    label: 'What are you looking for?',
                    controller: _nameCtrl,
                    hint: 'e.g. Vintage Levi\'s 501',
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<ProductCategory>(
                    // ignore: deprecated_member_use
                    value: _category,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    items: ProductCategory.values
                        .map(
                          (c) =>
                              DropdownMenuItem(value: c, child: Text(c.label)),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _category = v);
                    },
                  ),
                  const SizedBox(height: 16),
                  ThriftTextField(
                    label: 'Description',
                    controller: _descCtrl,
                    maxLines: 4,
                    hint:
                        'Describe the specific details, colors, or condition you want...',
                  ),
                  const SizedBox(height: 16),
                  ThriftTextField(
                    label: 'Preferred Size',
                    controller: _sizeCtrl,
                    hint: 'e.g. M, 32, One Size',
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ThriftTextField(
                          label: 'Budget Min (₱)',
                          controller: _minCtrl,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ThriftTextField(
                          label: 'Budget Max (₱)',
                          controller: _maxCtrl,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  ThriftButton(
                    label: _submitting
                        ? (_isEditing ? 'Saving…' : 'Posting…')
                        : (_isEditing ? 'Save Changes' : 'Post Request'),
                    onPressed: _submitting ? null : _submit,
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
