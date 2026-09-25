import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/smartads_api.dart';
import '../theme.dart';
import '../utils/formatting.dart';
import 'payment_dialog.dart';

class BookingSheet extends StatefulWidget {
  const BookingSheet({super.key, required this.api, required this.billboard});
  final SmartAdsApi api;
  final Map<String, dynamic> billboard;
  @override
  State<BookingSheet> createState() => _BookingSheetState();
}

enum SlotFilter { all, day, night }

class _BookingSheetState extends State<BookingSheet> {
  DateTime date = DateTime.now();
  List<String> allFreeSlots = [];
  final Set<String> selectedSlots = {};
  SlotFilter activeFilter = SlotFilter.all;
  bool loadingSlots = true;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _loadSlots();
  }

  String dateIso(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  bool _isDayHour(int hour) => hour >= 8 && hour < 20;

  List<String> get filteredSlots {
    if (activeFilter == SlotFilter.day) {
      return allFreeSlots.where((s) => _isDayHour(int.parse(s.substring(0, 2)))).toList();
    } else if (activeFilter == SlotFilter.night) {
      return allFreeSlots.where((s) => !_isDayHour(int.parse(s.substring(0, 2)))).toList();
    }
    return allFreeSlots;
  }

  String _formatSlotLabel(String start) {
    final hour = int.parse(start.substring(0, 2));
    final endHour = (hour + 1) % 24;
    return '$start–${endHour.toString().padLeft(2, '0')}:00';
  }

  Future<void> _loadSlots() async {
    setState(() {
      loadingSlots = true;
      selectedSlots.clear();
      error = null;
    });
    try {
      final response = await widget.api.get(
          '/api/billboards/${widget.billboard['id']}/availability?date=${dateIso(date)}');
      final booked = (response['bookedSlots'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final free = <String>[];
      // Full 24-hour slots: 00:00 to 23:00
      for (var hour = 0; hour < 24; hour++) {
        final start = '${hour.toString().padLeft(2, '0')}:00';
        final end = hour == 23 ? '23:59' : '${(hour + 1).toString().padLeft(2, '0')}:00';
        if (!booked.any((b) =>
            ('${b['start_time']}').compareTo(end) < 0 &&
            ('${b['end_time']}').compareTo(start) > 0)) {
          free.add(start);
        }
      }
      if (mounted) {
        setState(() {
          allFreeSlots = free;
          loadingSlots = false;
        });
      }
    } catch (exception) {
      if (mounted) {
        setState(() {
          error = cleanError(exception);
          loadingSlots = false;
        });
      }
    }
  }

  Future<void> _chooseDate() async {
    final chosen = await showDatePicker(
        context: context,
        initialDate: date,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365)));
    if (chosen != null) {
      date = chosen;
      await _loadSlots();
    }
  }

  void _selectAllVisible() {
    setState(() {
      selectedSlots.addAll(filteredSlots);
      error = null;
    });
  }

  void _clearSelection() {
    setState(() {
      selectedSlots.clear();
    });
  }

  Future<void> _continue() async {
    if (selectedSlots.isEmpty) {
      setState(() => error = 'Select at least one available time slot.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final selection = await FilePicker.platform
          .pickFiles(type: FileType.video, withData: true);
      if (selection == null || selection.files.isEmpty) {
        if (mounted) setState(() => busy = false);
        return;
      }
      final file = selection.files.first;
      final reviewResponse = await widget.api.uploadVideo(file);
      final review = Map<String, dynamic>.from(reviewResponse['review'] as Map);
      if (!mounted) return;

      final hourlyRate = (widget.billboard['price_per_hour'] as num).toDouble();
      final totalAmount = hourlyRate * selectedSlots.length;

      final payment = await showDialog<PaymentDetails>(
        context: context,
        builder: (_) => PaymentDialog(
          amount: totalAmount,
          slotCount: selectedSlots.length,
          reviewMessage: '${review['message']}',
        ),
      );
      if (payment == null || !mounted) {
        setState(() => busy = false);
        return;
      }

      // Sort slots chronologically
      final sortedSlots = selectedSlots.toList()..sort();

      final bookingResponse = await widget.api.post('/api/bookings', body: {
        'billboardId': widget.billboard['id'],
        'reviewId': review['id'],
        'date': dateIso(date),
        'slots': sortedSlots,
      });

      final List createdBookings = (bookingResponse['bookings'] as List?) ?? [bookingResponse['booking']];
      final bookingIds = createdBookings.map((b) => '${b['id']}').toList();

      await widget.api.post('/api/bookings/batch-pay', body: {
        'bookingIds': bookingIds,
        'provider': payment.provider,
        'mobileNumber': payment.mobileNumber,
      });

      if (mounted) Navigator.pop(context, true);
    } catch (exception) {
      if (mounted) {
        setState(() {
          error = cleanError(exception);
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final hourlyRate = (widget.billboard['price_per_hour'] as num).toDouble();
    final totalAmount = hourlyRate * selectedSlots.length;
    final displayedSlots = filteredSlots;

    return Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 26),
          decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
          child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    Center(
                        child: Container(
                            width: 42,
                            height: 4,
                            decoration: BoxDecoration(
                                color: const Color(0xFFDCE4E1),
                                borderRadius: BorderRadius.circular(9)))),
                    const SizedBox(height: 18),
                    Text('${widget.billboard['name']}',
                        style: const TextStyle(
                            color: ink,
                            fontSize: 21,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 5),
                    Text(
                        '${widget.billboard['location']}  ·  ${money(widget.billboard['price_per_hour'])}/hour',
                        style: const TextStyle(
                            color: Color(0xFF718186), fontSize: 13)),
                    const SizedBox(height: 22),
                    const Text('1. Choose a date',
                        style: TextStyle(
                            color: ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 14)),
                    const SizedBox(height: 9),
                    OutlinedButton.icon(
                        onPressed: busy ? null : _chooseDate,
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: Text(
                            '${date.day.toString().padLeft(2, '0')} ${monthName(date.month)} ${date.year}  ·  Change date'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: ink,
                            minimumSize: const Size.fromHeight(47),
                            alignment: Alignment.centerLeft,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13)))),
                    const SizedBox(height: 19),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('2. Select time slots (Multi-select)',
                            style: TextStyle(
                                color: ink,
                                fontWeight: FontWeight.w800,
                                fontSize: 14)),
                        if (!loadingSlots && allFreeSlots.isNotEmpty)
                          Row(
                            children: [
                              TextButton(
                                onPressed: busy ? null : _selectAllVisible,
                                style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                                child: const Text('Select all', style: TextStyle(fontSize: 12)),
                              ),
                              if (selectedSlots.isNotEmpty)
                                TextButton(
                                  onPressed: busy ? null : _clearSelection,
                                  style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      foregroundColor: Colors.redAccent,
                                      padding: const EdgeInsets.symmetric(horizontal: 8)),
                                  child: const Text('Clear', style: TextStyle(fontSize: 12)),
                                ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Filter tabs: All, Day, Night
                    if (!loadingSlots && allFreeSlots.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            FilterChip(
                              label: Text('All (${allFreeSlots.length})'),
                              selected: activeFilter == SlotFilter.all,
                              onSelected: (val) {
                                if (val) setState(() => activeFilter = SlotFilter.all);
                              },
                              selectedColor: const Color(0xFFDDF1EC),
                              labelStyle: TextStyle(
                                  color: activeFilter == SlotFilter.all ? teal : ink,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12),
                            ),
                            const SizedBox(width: 8),
                            FilterChip(
                              avatar: const Icon(Icons.wb_sunny_outlined, size: 15),
                              label: Text('☀️ Day (${allFreeSlots.where((s) => _isDayHour(int.parse(s.substring(0, 2)))).length})'),
                              selected: activeFilter == SlotFilter.day,
                              onSelected: (val) {
                                if (val) setState(() => activeFilter = SlotFilter.day);
                              },
                              selectedColor: const Color(0xFFDDF1EC),
                              labelStyle: TextStyle(
                                  color: activeFilter == SlotFilter.day ? teal : ink,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12),
                            ),
                            const SizedBox(width: 8),
                            FilterChip(
                              avatar: const Icon(Icons.nightlight_outlined, size: 15),
                              label: Text('🌙 Night (${allFreeSlots.where((s) => !_isDayHour(int.parse(s.substring(0, 2)))).length})'),
                              selected: activeFilter == SlotFilter.night,
                              onSelected: (val) {
                                if (val) setState(() => activeFilter = SlotFilter.night);
                              },
                              selectedColor: const Color(0xFFDDF1EC),
                              labelStyle: TextStyle(
                                  color: activeFilter == SlotFilter.night ? teal : ink,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12),
                            ),
                          ],
                        ),
                      ),

                    if (loadingSlots)
                      const Center(
                          child: Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator()))
                    else if (error != null && allFreeSlots.isEmpty)
                      Text(error!,
                          style: const TextStyle(
                              color: Color(0xFFAA4545), fontSize: 13))
                    else if (allFreeSlots.isEmpty)
                      const Text(
                          'No slots are available for this date. Try another day.',
                          style:
                              TextStyle(color: Color(0xFF718186), fontSize: 13))
                    else if (displayedSlots.isEmpty)
                      Text(
                          activeFilter == SlotFilter.night
                              ? 'No night slots available for this date.'
                              : 'No day slots available for this date.',
                          style: const TextStyle(color: Color(0xFF718186), fontSize: 13))
                    else
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final slot in displayedSlots)
                          FilterChip(
                              label: Text(_formatSlotLabel(slot)),
                              selected: selectedSlots.contains(slot),
                              onSelected: busy
                                  ? null
                                  : (value) => setState(() {
                                        if (value) {
                                          selectedSlots.add(slot);
                                        } else {
                                          selectedSlots.remove(slot);
                                        }
                                        error = null;
                                      }),
                              selectedColor: const Color(0xFFDDF1EC),
                              labelStyle: TextStyle(
                                  color: selectedSlots.contains(slot) ? teal : ink,
                                  fontWeight: FontWeight.w600),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(11)))
                      ]),

                    if (selectedSlots.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F8F6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFD0E8E2)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: teal, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${selectedSlots.length} slot${selectedSlots.length == 1 ? '' : 's'} selected (${selectedSlots.length} hr${selectedSlots.length == 1 ? '' : 's'})',
                                style: const TextStyle(fontWeight: FontWeight.w700, color: ink, fontSize: 13),
                              ),
                            ),
                            Text(
                              'Total: ${money(totalAmount)}',
                              style: const TextStyle(fontWeight: FontWeight.w900, color: teal, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),
                    const Text('3. Upload your advertisement video',
                        style: TextStyle(
                            color: ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 14)),
                    const SizedBox(height: 5),
                    const Text(
                        'MP4, MOV, M4V or WebM · up to 120 MB · max 3 minutes. Gemini AI will review your advertisement.',
                        style: TextStyle(
                            color: Color(0xFF7A8A8E),
                            height: 1.4,
                            fontSize: 12)),
                    if (error != null && allFreeSlots.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(error!,
                              style: const TextStyle(
                                  color: Color(0xFFAA4545), fontSize: 12))),
                    const SizedBox(height: 16),
                    SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                            onPressed: busy || loadingSlots || allFreeSlots.isEmpty || selectedSlots.isEmpty
                                ? null
                                : _continue,
                            icon: busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.upload_file_rounded),
                            label: Text(busy
                                ? 'Uploading & checking video…'
                                : selectedSlots.isEmpty
                                    ? 'Select time slots above'
                                    : 'Select video & book (${selectedSlots.length} slot${selectedSlots.length == 1 ? '' : 's'} · ${money(totalAmount)})'),
                            style: FilledButton.styleFrom(
                                backgroundColor: teal,
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(51),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14))))),
                  ]))),
        ));
  }
}
