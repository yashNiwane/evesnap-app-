import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/event_service.dart';
import '../theme/eve_palette.dart';

const double _coverAspectRatio = 16 / 9;

class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({super.key, required this.eventService});

  final EventService eventService;

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _pageController = PageController();
  final _nameController = TextEditingController();
  final _detailsController = TextEditingController();
  final _nameFocusNode = FocusNode();
  final _detailsFocusNode = FocusNode();
  final _nameFieldKey = GlobalKey();
  final _detailsFieldKey = GlobalKey();
  DateTime _revealTime = DateTime.now().add(const Duration(hours: 2));
  double _photoLimit = 20;
  String _theme = 'party';
  int _step = 0;
  bool _saving = false;
  bool _pickingCover = false;
  Uint8List? _coverBytes;
  String? _coverExt;

  static const _themes = [
    ('minimal', 'Minimal'),
    ('party', 'Party'),
    ('wedding', 'Wedding'),
    ('vacation', 'Vacation'),
    ('graduation', 'Graduation'),
    ('birthday', 'Birthday'),
    ('festival', 'Festival'),
  ];

  static const _guestPromptSamples = [
    'Capture candid photos, big smiles, and all the little in-between moments.',
    'Record short videos of reactions, cheers, and the best highlights.',
    'Take group shots, solo portraits, and fun behind-the-scenes clips.',
    'Document the vibe from start to finish with photos and quick reels.',
  ];

  @override
  void initState() {
    super.initState();
    _nameFocusNode.addListener(() {
      if (_nameFocusNode.hasFocus) {
        _scrollFocusedFieldIntoView(_nameFieldKey);
      }
    });
    _detailsFocusNode.addListener(() {
      if (_detailsFocusNode.hasFocus) {
        _scrollFocusedFieldIntoView(_detailsFieldKey);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _detailsController.dispose();
    _nameFocusNode.dispose();
    _detailsFocusNode.dispose();
    super.dispose();
  }

  void _scrollFocusedFieldIntoView(GlobalKey fieldKey) {
    Future<void>.delayed(const Duration(milliseconds: 320), () {
      final fieldContext = fieldKey.currentContext;
      if (!mounted || fieldContext == null || !fieldContext.mounted) {
        return;
      }

      Scrollable.ensureVisible(
        fieldContext,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.64,
      );
    });
  }

  Future<void> _pickRevealTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _revealTime,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_revealTime),
    );
    if (time == null) return;

    setState(() {
      _revealTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _next() async {
    if (_step == 0 && _nameController.text.trim().isEmpty) {
      _showMessage('Give your event a name first.');
      return;
    }

    if (_step < 4) {
      await _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    await _submit();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showMessage('Give your event a name first.');
      return;
    }
    if (!_revealTime.isAfter(DateTime.now())) {
      _showMessage('Choose a reveal time in the future.');
      return;
    }

    setState(() => _saving = true);
    try {
      final event = await widget.eventService.createEvent(
        name: name,
        details: _detailsController.text.trim(),
        theme: _theme,
        revealTime: _revealTime,
        photoLimit: _photoLimit.round(),
      );

      if (_coverBytes != null) {
        try {
          final ext = _coverExt ?? 'jpg';
          final coverPath = await widget.eventService.uploadEventCover(
            eventId: event.id,
            bytes: _coverBytes!,
            fileExt: ext,
          );
          await widget.eventService.attachEventCover(
            eventId: event.id,
            coverPath: coverPath,
          );
          event.coverPath = coverPath;
          event.coverSignedUrl = await widget.eventService.createCoverSignedUrl(
            coverPath,
          );
        } catch (e) {
          if (mounted) {
            _showMessage(
              'Event created, but cover upload failed. You can add a cover later. (${_friendlyError(e)})',
            );
          }
        }
      }
      if (!mounted) return;
      Navigator.pop(context, event);
    } catch (e) {
      if (!mounted) return;
      _showMessage('Failed to create event: ${_friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _friendlyError(Object error) {
    if (error is PostgrestException) {
      final code = error.code == null || error.code!.isEmpty
          ? ''
          : ' [${error.code}]';
      return '${error.message}$code';
    }
    if (error is StorageException) {
      final status = error.statusCode == null ? '' : ' [${error.statusCode}]';
      return '${error.message}$status';
    }
    return error.toString();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickCoverImage() async {
    if (_pickingCover || _saving) {
      return;
    }

    setState(() => _pickingCover = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 1800,
      );
      if (picked == null) {
        return;
      }

      final originalBytes = await picked.readAsBytes();
      if (originalBytes.isEmpty) {
        _showMessage('Could not read selected image.');
        return;
      }
      if (!mounted) return;

      final croppedBytes = await Navigator.push<Uint8List>(
        context,
        MaterialPageRoute(
          builder: (_) => _CoverCropScreen(imageBytes: originalBytes),
        ),
      );
      if (!mounted) return;
      if (croppedBytes == null || croppedBytes.isEmpty) {
        return;
      }

      setState(() {
        _coverBytes = croppedBytes;
        _coverExt = _fileExtFromPath(picked.path);
      });
    } catch (_) {
      _showMessage('Could not pick cover image. Please retry.');
    } finally {
      if (mounted) {
        setState(() => _pickingCover = false);
      }
    }
  }

  String _fileExtFromPath(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) {
      return 'jpg';
    }
    return path.substring(dot + 1).toLowerCase();
  }

  void _applyGuestPrompt(String prompt) {
    _detailsController.text = prompt;
    _detailsController.selection = TextSelection.fromPosition(
      TextPosition(offset: prompt.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EvePalette.night,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: _step == 0 ? 'Close' : 'Back',
                    onPressed: _saving ? null : _back,
                    icon: Icon(
                      _step == 0
                          ? Icons.close_rounded
                          : Icons.arrow_back_rounded,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'New event',
                    style: GoogleFonts.spaceGrotesk(
                      color: EvePalette.bone,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) => setState(() => _step = index),
                children: [
                  _EventNameStep(
                    fieldKey: _nameFieldKey,
                    controller: _nameController,
                    focusNode: _nameFocusNode,
                    coverBytes: _coverBytes,
                    pickingCover: _pickingCover,
                    onPickCover: _pickCoverImage,
                  ),
                  _DetailsStep(
                    fieldKey: _detailsFieldKey,
                    controller: _detailsController,
                    focusNode: _detailsFocusNode,
                    promptSamples: _guestPromptSamples,
                    onSampleTap: _applyGuestPrompt,
                  ),
                  _ThemeStep(
                    themes: _themes,
                    selectedTheme: _theme,
                    onChanged: (value) => setState(() => _theme = value),
                  ),
                  _RevealStep(
                    revealTime: _revealTime,
                    onPickRevealTime: _pickRevealTime,
                  ),
                  _LimitStep(
                    photoLimit: _photoLimit,
                    onChanged: (value) => setState(() => _photoLimit = value),
                  ),
                ],
              ),
            ),
            AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
              child: Row(
                children: [
                  Expanded(child: _StepDots(currentStep: _step, steps: 5)),
                  FilledButton.icon(
                    onPressed: _saving ? null : _next,
                    style: FilledButton.styleFrom(
                      backgroundColor: EvePalette.bone,
                      foregroundColor: EvePalette.ink,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    label: Text(
                      _saving
                          ? 'Creating...'
                          : (_step == 4 ? 'Create' : 'Next'),
                      style: GoogleFonts.manrope(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    icon: Icon(
                      _step == 4
                          ? Icons.check_rounded
                          : Icons.arrow_forward_rounded,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _back() async {
    if (_step == 0) {
      Navigator.pop(context);
      return;
    }

    await _pageController.previousPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }
}

class _EventNameStep extends StatelessWidget {
  const _EventNameStep({
    required this.fieldKey,
    required this.controller,
    required this.focusNode,
    required this.coverBytes,
    required this.pickingCover,
    required this.onPickCover,
  });

  final GlobalKey fieldKey;
  final TextEditingController controller;
  final FocusNode focusNode;
  final Uint8List? coverBytes;
  final bool pickingCover;
  final VoidCallback onPickCover;

  @override
  Widget build(BuildContext context) {
    return _FlowPage(
      media: _CoverPreview(
        coverBytes: coverBytes,
        pickingCover: pickingCover,
        onPickCover: onPickCover,
      ),
      title: 'What should we call this Event?',
      child: TextField(
        key: fieldKey,
        controller: controller,
        focusNode: focusNode,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        style: GoogleFonts.spaceGrotesk(color: EvePalette.bone, fontSize: 18),
        decoration: const InputDecoration(
          hintText: "New year's eve",
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(24)),
          ),
        ),
      ),
    );
  }
}

class _DetailsStep extends StatelessWidget {
  const _DetailsStep({
    required this.fieldKey,
    required this.controller,
    required this.focusNode,
    required this.promptSamples,
    required this.onSampleTap,
  });

  final GlobalKey fieldKey;
  final TextEditingController controller;
  final FocusNode focusNode;
  final List<String> promptSamples;
  final ValueChanged<String> onSampleTap;

  @override
  Widget build(BuildContext context) {
    return _FlowPage(
      title: 'What should guests know?',
      subtitle: 'A short note helps everyone capture the right mood.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: fieldKey,
            controller: controller,
            focusNode: focusNode,
            minLines: 4,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            style: GoogleFonts.spaceGrotesk(
              color: EvePalette.bone,
              fontSize: 17,
            ),
            decoration: const InputDecoration(
              hintText: 'Dress code, timing, location, or the vibe...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(24)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Quick examples',
            style: GoogleFonts.spaceGrotesk(
              color: EvePalette.muted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final sample in promptSamples)
                ActionChip(
                  onPressed: () => onSampleTap(sample),
                  backgroundColor: EvePalette.coal,
                  side: const BorderSide(color: EvePalette.line),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  label: Text(
                    sample,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceGrotesk(
                      color: EvePalette.bone,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThemeStep extends StatelessWidget {
  const _ThemeStep({
    required this.themes,
    required this.selectedTheme,
    required this.onChanged,
  });

  final List<(String, String)> themes;
  final String selectedTheme;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return _FlowPage(
      title: 'Choose a feeling for it.',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final theme in themes)
            ChoiceChip(
              selected: selectedTheme == theme.$1,
              label: Text(theme.$2),
              onSelected: (_) => onChanged(theme.$1),
              labelStyle: GoogleFonts.spaceGrotesk(
                color: selectedTheme == theme.$1
                    ? EvePalette.ink
                    : EvePalette.bone,
                fontWeight: FontWeight.w800,
              ),
              selectedColor: EvePalette.bone,
              backgroundColor: EvePalette.coal,
              side: const BorderSide(color: EvePalette.line),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
        ],
      ),
    );
  }
}

class _RevealStep extends StatelessWidget {
  const _RevealStep({required this.revealTime, required this.onPickRevealTime});

  final DateTime revealTime;
  final VoidCallback onPickRevealTime;

  @override
  Widget build(BuildContext context) {
    final local = TimeOfDay.fromDateTime(revealTime).format(context);

    return _FlowPage(
      title: 'When should the Event unlock?',
      subtitle: 'Guests can view the full gallery after this time.',
      child: ListTile(
        onTap: onPickRevealTime,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: EvePalette.line),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 12,
        ),
        title: Text(
          '${revealTime.day}/${revealTime.month}/${revealTime.year}',
          style: GoogleFonts.spaceGrotesk(
            color: EvePalette.bone,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          local,
          style: GoogleFonts.spaceGrotesk(color: EvePalette.muted),
        ),
        trailing: const Icon(Icons.edit_calendar_rounded),
      ),
    );
  }
}

class _LimitStep extends StatelessWidget {
  const _LimitStep({required this.photoLimit, required this.onChanged});

  final double photoLimit;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return _FlowPage(
      title: 'How many photos per guest?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${photoLimit.round()} photos',
            style: GoogleFonts.spaceGrotesk(
              color: EvePalette.bone,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          Slider(
            value: photoLimit,
            min: 5,
            max: 100,
            divisions: 19,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _FlowPage extends StatelessWidget {
  const _FlowPage({
    required this.title,
    required this.child,
    this.subtitle,
    this.media,
  });

  final String title;
  final String? subtitle;
  final Widget? media;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
      padding: EdgeInsets.fromLTRB(28, 10, 28, 120 + keyboardInset),
      children: [
        media ?? const SizedBox(height: 130),
        const SizedBox(height: 28),
        Text(
          title,
          style: GoogleFonts.dmSerifDisplay(
            color: EvePalette.bone,
            fontSize: 46,
            height: 1.02,
            fontWeight: FontWeight.w400,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 12),
          Text(
            subtitle!,
            style: GoogleFonts.spaceGrotesk(
              color: EvePalette.muted,
              fontSize: 16,
              height: 1.35,
            ),
          ),
        ],
        const SizedBox(height: 36),
        child,
      ],
    );
  }
}

class _CoverPreview extends StatelessWidget {
  const _CoverPreview({
    required this.coverBytes,
    required this.pickingCover,
    required this.onPickCover,
  });

  final Uint8List? coverBytes;
  final bool pickingCover;
  final VoidCallback onPickCover;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: AspectRatio(
            aspectRatio: _coverAspectRatio,
            child: coverBytes != null
                ? Image.memory(
                    coverBytes!,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.low,
                  )
                : Image.asset(
                    'assets/images/minimalcamera.jpg',
                    fit: BoxFit.cover,
                    color: EvePalette.sage,
                    colorBlendMode: BlendMode.modulate,
                  ),
          ),
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: pickingCover ? null : onPickCover,
          style: OutlinedButton.styleFrom(
            foregroundColor: EvePalette.bone,
            side: const BorderSide(color: EvePalette.line),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          icon: pickingCover
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_rounded),
          label: Text(
            coverBytes != null ? 'Change Cover' : 'Add Cover',
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _CoverCropScreen extends StatefulWidget {
  const _CoverCropScreen({required this.imageBytes});

  final Uint8List imageBytes;

  @override
  State<_CoverCropScreen> createState() => _CoverCropScreenState();
}

class _CoverCropScreenState extends State<_CoverCropScreen> {
  final CropController _controller = CropController();
  bool _submitting = false;

  void _submitCrop() {
    if (_submitting) return;
    setState(() => _submitting = true);
    _controller.crop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EvePalette.ink,
      appBar: AppBar(
        title: const Text('Crop Cover'),
        actions: [
          FilledButton(
            onPressed: _submitting ? null : _submitCrop,
            style: FilledButton.styleFrom(
              backgroundColor: EvePalette.bone,
              foregroundColor: EvePalette.ink,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              'Set',
              style: GoogleFonts.dmSerifDisplay(
                fontSize: 19,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Crop(
        image: widget.imageBytes,
        controller: _controller,
        aspectRatio: _coverAspectRatio,
        baseColor: EvePalette.ink,
        maskColor: Colors.black.withValues(alpha: 0.55),
        onCropped: (result) {
          if (!mounted) return;
          switch (result) {
            case CropSuccess(:final croppedImage):
              Navigator.pop(context, croppedImage);
            case CropFailure():
              setState(() => _submitting = false);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Could not crop image.')),
              );
          }
        },
      ),
    );
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.currentStep, required this.steps});

  final int currentStep;
  final int steps;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int index = 0; index < steps; index++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.symmetric(horizontal: 5),
            width: currentStep == index ? 10 : 8,
            height: currentStep == index ? 10 : 8,
            decoration: BoxDecoration(
              color: currentStep == index ? EvePalette.bone : EvePalette.line,
              shape: BoxShape.circle,
            ),
          ),
      ],
    );
  }
}
