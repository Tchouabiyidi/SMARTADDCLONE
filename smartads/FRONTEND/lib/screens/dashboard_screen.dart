import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/smartads_api.dart';
import '../theme.dart';
import '../utils/formatting.dart';
import 'booking_sheet.dart';

/// SQLite stores booleans as 0/1 integers, but JS `true`/`false` values
/// seeded by Sequelize may arrive as Dart [bool] from JSON. This helper
/// handles both representations safely.
bool _isActive(Map<String, dynamic> board) {
  final v = board['is_active'];
  if (v is bool) return v;
  if (v is num) return v != 0;
  return false;
}


class DashboardScreen extends StatefulWidget {
  const DashboardScreen(
      {super.key,
      required this.api,
      required this.user,
      required this.onSignOut});
  final SmartAdsApi api;
  final Map<String, dynamic> user;
  final Future<void> Function() onSignOut;
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int tab = 0;
  bool loading = true;
  List<Map<String, dynamic>> billboards = [];
  List<Map<String, dynamic>> bookings = [];
  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> devices = [];
  String get role => widget.user['role'] as String;
  String get roleName => switch (role) {
        'owner' => 'Billboard owner',
        'admin' => 'Administrator',
        _ => 'Advertiser'
      };
  List<String> get labels => switch (role) {
        'owner' => ['My billboards', 'Schedules', 'Account'],
        'admin' => ['Billboards', 'Schedules', 'Users', 'Account'],
        _ => ['Explore', 'My bookings', 'Account']
      };
  List<IconData> get icons => switch (role) {
        'owner' => [
            Icons.dashboard_outlined,
            Icons.calendar_month_outlined,
            Icons.person_outline
          ],
        'admin' => [
            Icons.location_city_outlined,
            Icons.calendar_month_outlined,
            Icons.group_outlined,
            Icons.person_outline
          ],
        _ => [
            Icons.explore_outlined,
            Icons.calendar_month_outlined,
            Icons.person_outline
          ]
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => loading = true);
    try {
      final results = await Future.wait([
        widget.api.get('/api/billboards'),
        widget.api.get('/api/bookings'),
        if (role == 'admin') widget.api.get('/api/admin/users'),
        if (role == 'owner' || role == 'admin')
          widget.api.get('/api/tv/devices'),
      ]);
      billboards = (results[0]['billboards'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      bookings = (results[1]['bookings'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      if (role == 'admin') {
        users = (results[2]['users'] as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        devices = (results[3]['devices'] as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      } else if (role == 'owner') {
        devices = (results[2]['devices'] as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      }
    } catch (error) {
      if (mounted) showMessage(context, cleanError(error));
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _createBillboard() async {
    final result = await showDialog<Map<String, dynamic>>(
        context: context, builder: (_) => const CreateBillboardDialog());
    if (result == null) return;
    try {
      await widget.api.post('/api/billboards', body: result);
      await _load();
      if (mounted) showMessage(context, 'Billboard added to your listings.');
    } catch (error) {
      if (mounted) showMessage(context, cleanError(error));
    }
  }

  Future<void> _book(Map<String, dynamic> billboard) async {
    final completed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BookingSheet(api: widget.api, billboard: billboard),
    );
    if (completed == true) {
      await _load();
      if (mounted) {
        showMessage(context, 'Your advertisement is confirmed and scheduled.');
      }
    }
  }

  Future<void> _toggleBoard(Map<String, dynamic> board) async {
    try {
      await widget.api.patch('/api/billboards/${board['id']}',
          body: {'isActive': !_isActive(board)});
      await _load();
      if (mounted) {
        showMessage(
            context,
            _isActive(board)
                ? 'Billboard set to offline.'
                : 'Billboard set to online.');
      }
    } catch (error) {
      if (mounted) showMessage(context, cleanError(error));
    }
  }

  Future<void> _setUserStatus(
      Map<String, dynamic> account, String status) async {
    try {
      await widget.api
          .patch('/api/admin/users/${account['id']}', body: {'status': status});
      await _load();
    } catch (error) {
      if (mounted) showMessage(context, cleanError(error));
    }
  }

  Future<void> _deleteUser(Map<String, dynamic> account) async {
    final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Delete this account?'),
              content: Text(
                  'Delete ${account['name']} and their related SMARTADS data?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Delete'))
              ],
            ));
    if (confirm != true) return;
    try {
      await widget.api.delete('/api/admin/users/${account['id']}');
      await _load();
    } catch (error) {
      if (mounted) showMessage(context, cleanError(error));
    }
  }

  Future<void> _pairTv() async {
    // Opens the unified QR+Code dialog; returns either a smartads://pair URI
    // (from QR scan) or a bare 8-char user code (from manual entry).
    final data = await showDialog<String>(
        context: context, builder: (_) => const PairTvDialog());
    if (data == null || !mounted) return;
    try {
      String? session;
      String? secret;
      String userCode;

      if (data.startsWith('smartads://pair')) {
        // Parsed from QR
        final uri = Uri.parse(data);
        session = uri.queryParameters['session'];
        secret = uri.queryParameters['secret'];
        userCode = uri.queryParameters['code'] ?? '';
        if (session == null || secret == null) {
          throw Exception('The pairing code is incomplete.');
        }
      } else {
        // Manual code entry — look up session by user code
        userCode = data.trim().toUpperCase();
        final lookup = await widget.api
            .get('/api/tv/pairings/lookup?code=${Uri.encodeQueryComponent(userCode)}');
        session = '${lookup['sessionId']}';
        // No secret available from code-only path; backend handles it
        secret = null;
        userCode = '${lookup['userCode']}';
      }

      // Build billboard list based on role
      final List<Map<String, dynamic>> eligible;
      if (role == 'admin') {
        eligible = billboards;
      } else if (role == 'owner') {
        eligible = billboards
            .where((item) => item['owner_id'] == widget.user['id'])
            .toList();
      } else {
        // Advertiser: only billboards with their confirmed bookings
        final bookedBillboardIds =
            bookings.where((b) => b['status'] == 'confirmed').map((b) => '${b['billboard_id']}').toSet();
        eligible = billboards
            .where((item) => bookedBillboardIds.contains('${item['id']}'))
            .toList();
        if (eligible.isEmpty) {
          throw Exception('You need at least one confirmed booking on a billboard before you can pair its TV.');
        }
      }

      if (!mounted) return;
      final board = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (_) => SelectBillboardDialog(
              billboards: eligible, userCode: userCode));
      if (board == null || !mounted) return;

      await widget.api.post('/api/tv/pairings/$session/approve', body: {
        if (secret != null) 'secret': secret,
        if (secret == null) 'userCode': userCode,
        'billboardId': board['id'],
      });
      if (role != 'advertiser') await _load();
      if (mounted) showMessage(context, 'TV connected to ${board['name']}.');
    } catch (error) {
      if (mounted) showMessage(context, cleanError(error));
    }
  }

  Future<void> _revokeTv(Map<String, dynamic> device) async {
    try {
      await widget.api.delete('/api/tv/devices/${device['id']}');
      await _load();
      if (mounted) showMessage(context, 'TV disconnected.');
    } catch (error) {
      if (mounted) showMessage(context, cleanError(error));
    }
  }

  Future<void> _stopBooking(Map<String, dynamic> booking) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              title: const Text('Stop this advertisement?'),
              content: const Text(
                  'Connected TVs will stop it immediately. Offline TVs stop when they reconnect or at the cached end time.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Stop advert')),
              ],
            ));
    if (confirmed != true) return;
    try {
      await widget.api.post('/api/admin/bookings/${booking['id']}/stop',
          body: {'reason': 'Stopped from admin dashboard'});
      await _load();
    } catch (error) {
      if (mounted) showMessage(context, cleanError(error));
    }
  }

  Future<void> _extendBooking(Map<String, dynamic> booking) async {
    final current = '${booking['end_time']}'.split(':');
    final selected = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(
            hour: int.parse(current[0]), minute: int.parse(current[1])));
    if (selected == null) return;
    final endTime =
        '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}';
    try {
      await widget.api.patch('/api/admin/bookings/${booking['id']}/extend',
          body: {
            'endTime': endTime,
            'reason': 'Extended from admin dashboard'
          });
      await _load();
    } catch (error) {
      if (mounted) showMessage(context, cleanError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = role == 'admin'
        ? switch (tab) {
            0 => _adminBoardsPage(),
            1 => _schedulePage(),
            2 => _usersPage(),
            _ => _accountPage(),
          }
        : switch (tab) {
            0 => role == 'owner' ? _boardPage() : _explorePage(),
            1 => _schedulePage(),
            _ => _accountPage(),
          };
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                  color: teal, borderRadius: BorderRadius.circular(11)),
              child: const Icon(Icons.play_arrow_rounded,
                  color: Colors.white, size: 25)),
          const SizedBox(width: 9),
          const Text('SMARTADS',
              style: TextStyle(
                  fontSize: 17,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w900))
        ]),
        actions: [
          IconButton(
              onPressed: _load,
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded)),
          const SizedBox(width: 6)
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _load, child: page),
      floatingActionButton: role == 'owner' && tab == 0
          ? FloatingActionButton.extended(
              onPressed: _createBillboard,
              icon: const Icon(Icons.add),
              label: const Text('Add billboard'))
          : null,
      bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (value) => setState(() => tab = value),
          destinations: [
            for (var i = 0; i < labels.length; i++)
              NavigationDestination(icon: Icon(icons[i]), label: labels[i])
          ]),
    );
  }

  Widget _pagePadding(Widget child) => ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 96), children: [child]);

  Widget _welcome(
          {required String title,
          required String subtitle,
          required IconData icon}) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
            color: ink,
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
                colors: [Color(0xFF1C4651), Color(0xFF142D3B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight)),
        child: Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                    'HELLO, ${(widget.user['name'] as String).split(' ').first.toUpperCase()}',
                    style: const TextStyle(
                        color: Color(0xFF92D9CC),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        fontSize: 10)),
                const SizedBox(height: 9),
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(subtitle,
                    style: const TextStyle(
                        color: Color(0xFFCBD8DA), fontSize: 13, height: 1.4))
              ])),
          const SizedBox(width: 12),
          Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .1),
                  shape: BoxShape.circle),
              child: Icon(icon, color: const Color(0xFF91DFCF), size: 29))
        ]),
      );

  Widget _section(String title, {String? trailing}) => Padding(
      padding: const EdgeInsets.fromLTRB(2, 24, 2, 12),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(title,
            style: const TextStyle(
                color: ink, fontSize: 17, fontWeight: FontWeight.w800)),
        if (trailing != null)
          Text(trailing,
              style: const TextStyle(color: Color(0xFF859397), fontSize: 12))
      ]));

  Widget _explorePage() => _pagePadding(
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _welcome(
            title: 'Find your next\nbig screen.',
            subtitle: 'Browse locations and reserve a time for your campaign.',
            icon: Icons.campaign_outlined),
        // Advertisers can pair a TV to any billboard where they have a booking
        if (bookings.any((b) => b['status'] == 'confirmed'))
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF9F7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFB6E2DB)),
            ),
            child: Row(children: [
              const Icon(Icons.tv_rounded, color: teal, size: 22),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Connect a display TV',
                        style: TextStyle(
                            color: ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 13)),
                    SizedBox(height: 2),
                    Text(
                        'Pair the TV at a billboard where your ad is confirmed.',
                        style: TextStyle(
                            color: Color(0xFF4A7570),
                            fontSize: 11,
                            height: 1.4)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                  onPressed: _pairTv,
                  style: FilledButton.styleFrom(
                      backgroundColor: teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                  label: const Text('Pair TV',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700))),
            ]),
          ),
        _section('Available billboards',
            trailing: '${billboards.length} locations'),
        if (billboards.isEmpty)
          const _EmptyCard(
              icon: Icons.location_city_outlined,
              title: 'No billboards yet',
              text: 'New locations will appear here as owners join SMARTADS.'),
        for (final board in billboards)
          BillboardCard(
              board: board,
              actionLabel: 'Book a slot',
              actionIcon: Icons.arrow_forward_rounded,
              onAction: () => _book(board)),
      ]));

  Widget _boardPage() {
    final activeCount =
        billboards.where((board) => _isActive(board)).length;
    return _pagePadding(
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _welcome(
          title: 'Your screens,\nyour schedule.',
          subtitle: 'Manage your billboard listings and availability.',
          icon: Icons.dashboard_outlined),
      const SizedBox(height: 17),
      Row(children: [
        _MetricCard(
            label: 'LISTED',
            value: '${billboards.length}',
            icon: Icons.location_city_outlined),
        const SizedBox(width: 10),
        _MetricCard(
            label: 'ONLINE',
            value: '$activeCount',
            icon: Icons.power_settings_new_rounded)
      ]),
      _section('Your billboards', trailing: 'Tap power to change status'),
      _tvDevicesCard(),
      if (billboards.isEmpty)
        const _EmptyCard(
            icon: Icons.add_business_outlined,
            title: 'List your first billboard',
            text:
                'Add its location, hourly rate and details to start receiving bookings.'),
      for (final board in billboards)
        BillboardCard(
            board: board, ownerMode: true, onAction: () => _toggleBoard(board)),
    ]));
  }

  Widget _tvDevicesCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 13),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE9EFEC)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.tv_rounded, color: teal),
        const SizedBox(width: 11),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              '${devices.length} connected TV${devices.length == 1 ? '' : 's'}',
              style: const TextStyle(
                  color: ink, fontWeight: FontWeight.w800, fontSize: 13),
            ),
            const SizedBox(height: 4),
            if (devices.isEmpty)
              const Text(
                'Install SMARTADS on Android TV, then scan its QR code.',
                style: TextStyle(
                    color: Color(0xFF718186), height: 1.35, fontSize: 11),
              )
            else
              for (final device in devices)
                Row(children: [
                  Expanded(
                      child: Text(
                          '${device['name']} · ${device['billboard_name']} · ${device['online'] == true ? 'online' : 'offline'}',
                          style: const TextStyle(
                              color: Color(0xFF718186), fontSize: 11))),
                  IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Disconnect TV',
                      onPressed: () => _revokeTv(device),
                      icon: const Icon(Icons.link_off_rounded, size: 17)),
                ]),
          ]),
        ),
        IconButton(
            tooltip: 'Scan TV QR code',
            onPressed: _pairTv,
            icon: const Icon(Icons.qr_code_scanner_rounded)),
      ]),
    );
  }

  Widget _adminBoardsPage() => _pagePadding(
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _welcome(
            title: 'Platform overview.',
            subtitle: 'Review billboard listings registered in SMARTADS.',
            icon: Icons.admin_panel_settings_outlined),
        _section('Registered billboards',
            trailing: '${billboards.length} total'),
        _tvDevicesCard(),
        if (billboards.isEmpty)
          const _EmptyCard(
              icon: Icons.location_city_outlined,
              title: 'No listings yet',
              text: 'Billboards registered by owners will appear here.'),
        for (final board in billboards)
          BillboardCard(board: board, adminMode: true),
      ]));

  Widget _schedulePage() => _pagePadding(
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _welcome(
            title: role == 'owner'
                ? 'Bookings and\nschedules.'
                : 'Your campaign\nschedule.',
            subtitle: role == 'owner'
                ? 'Upcoming ads booked on your billboards.'
                : 'Keep track of your confirmed advertisement bookings.',
            icon: Icons.calendar_month_outlined),
        _section(role == 'owner' ? 'Bookings on your screens' : 'Your bookings',
            trailing: '${bookings.length} total'),
        if (bookings.isEmpty)
          _EmptyCard(
              icon: Icons.event_available_outlined,
              title: 'Nothing scheduled yet',
              text: role == 'owner'
                  ? 'New bookings will appear here.'
                  : 'Once you book a billboard, your campaign schedule will appear here.'),
        for (final booking in bookings)
          BookingCard(
              booking: booking,
              role: role,
              onStop: role == 'admin' && booking['status'] == 'confirmed'
                  ? () => _stopBooking(booking)
                  : null,
              onExtend: role == 'admin' && booking['status'] == 'confirmed'
                  ? () => _extendBooking(booking)
                  : null),
      ]));

  Widget _usersPage() => _pagePadding(
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _welcome(
            title: 'User management.',
            subtitle: 'Review and manage advertiser and owner accounts.',
            icon: Icons.manage_accounts_outlined),
        _section('SMARTADS accounts', trailing: '${users.length} users'),
        if (users.isEmpty)
          const _EmptyCard(
              icon: Icons.group_outlined,
              title: 'No user accounts',
              text: 'Accounts created on the platform will appear here.'),
        for (final account in users)
          UserCard(
              account: account,
              onSuspend: () => _setUserStatus(account, 'suspended'),
              onActivate: () => _setUserStatus(account, 'active'),
              onDelete: () => _deleteUser(account)),
      ]));

  Widget _accountPage() => _pagePadding(
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _welcome(
            title: 'Your account.',
            subtitle: 'Manage your SMARTADS sign-in session.',
            icon: Icons.person_outline),
        const SizedBox(height: 20),
        Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Column(children: [
              _AccountRow(
                  icon: Icons.person_outline,
                  label: 'Name',
                  value: '${widget.user['name']}'),
              const Divider(height: 24),
              _AccountRow(
                  icon: Icons.mail_outline,
                  label: 'Email',
                  value: '${widget.user['email']}'),
              const Divider(height: 24),
              _AccountRow(
                  icon: Icons.badge_outlined,
                  label: 'Account type',
                  value: roleName),
            ])),
        const SizedBox(height: 16),
        OutlinedButton.icon(
            onPressed: () => widget.onSignOut(),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
            style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF9B4141),
                minimumSize: const Size.fromHeight(50),
                side: const BorderSide(color: Color(0xFFEBDADA)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)))),
        if (role == 'admin')
          const Padding(
              padding: EdgeInsets.only(top: 20),
              child: Text(
                  'Admin accounts are configured by the backend administrator.',
                  style: TextStyle(
                      color: Color(0xFF7A898D), fontSize: 12, height: 1.5))),
      ]));
}

class BillboardCard extends StatelessWidget {
  const BillboardCard(
      {super.key,
      required this.board,
      this.actionLabel,
      this.actionIcon,
      this.onAction,
      this.ownerMode = false,
      this.adminMode = false});
  final Map<String, dynamic> board;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  final bool ownerMode;
  final bool adminMode;
  @override
  Widget build(BuildContext context) {
    final active = _isActive(board);
    return Container(
      margin: const EdgeInsets.only(bottom: 13),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE9EFEC))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                  color: const Color(0xFFE7F3F0),
                  borderRadius: BorderRadius.circular(15)),
              child: const Icon(Icons.tv_outlined, color: teal, size: 27)),
          const SizedBox(width: 13),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('${board['name']}',
                    style: const TextStyle(
                        color: ink, fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 5),
                Row(children: [
                  const Icon(Icons.location_on_outlined,
                      size: 14, color: Color(0xFF7D8E91)),
                  const SizedBox(width: 3),
                  Expanded(
                      child: Text('${board['location']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Color(0xFF718186), fontSize: 12)))
                ]),
                if (adminMode)
                  Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text('Owner: ${board['owner_name'] ?? '—'}',
                          style: const TextStyle(
                              color: Color(0xFF879498), fontSize: 11)))
              ])),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(money(board['price_per_hour']),
                style: const TextStyle(
                    color: ink, fontWeight: FontWeight.w800, fontSize: 15)),
            const Text('per hour',
                style: TextStyle(color: Color(0xFF879498), fontSize: 10))
          ]),
        ]),
        if ('${board['description'] ?? ''}'.isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('${board['description']}',
                  style: const TextStyle(
                      color: Color(0xFF64767B), height: 1.45, fontSize: 12))),
        if (ownerMode)
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Row(children: [
              Expanded(
                child: Text('Playback ID: ${board['id']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFF879498), fontSize: 10)),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Copy billboard ID for backend setup',
                icon: const Icon(Icons.copy_rounded, size: 15),
                onPressed: () async {
                  await Clipboard.setData(
                      ClipboardData(text: '${board['id']}'));
                  if (context.mounted) {
                    showMessage(context, 'Billboard ID copied.');
                  }
                },
              ),
            ]),
          ),
        if (ownerMode || adminMode)
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(children: [
                Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                        color: active ? teal : const Color(0xFFB8C1C1),
                        shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(active ? 'Online for bookings' : 'Offline',
                    style: TextStyle(
                        color: active ? teal : const Color(0xFF879498),
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                if (ownerMode)
                  IconButton(
                      onPressed: onAction,
                      visualDensity: VisualDensity.compact,
                      tooltip: active ? 'Turn off' : 'Turn on',
                      icon: Icon(Icons.power_settings_new_rounded,
                          color: active ? teal : const Color(0xFF9BA8A8)))
              ])),
        if (actionLabel != null)
          Padding(
              padding: const EdgeInsets.only(top: 14),
              child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                      onPressed: active ? onAction : null,
                      icon: Icon(actionIcon, size: 17),
                      label: Text(actionLabel!),
                      style: FilledButton.styleFrom(
                          foregroundColor: teal,
                          backgroundColor: const Color(0xFFE7F3F0),
                          minimumSize: const Size.fromHeight(43),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)))))),
      ]),
    );
  }
}

class BookingCard extends StatelessWidget {
  const BookingCard(
      {super.key,
      required this.booking,
      required this.role,
      this.onStop,
      this.onExtend});
  final Map<String, dynamic> booking;
  final String role;
  final VoidCallback? onStop;
  final VoidCallback? onExtend;
  @override
  Widget build(BuildContext context) {
    final confirmed = booking['status'] == 'confirmed';
    final date = DateTime.tryParse('${booking['booking_date']}T00:00:00');
    final dateText = date == null
        ? '${booking['booking_date']}'
        : '${date.day.toString().padLeft(2, '0')} ${monthName(date.month)} ${date.year}';
    return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE8EEEB))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text('${booking['billboard_name']}',
                    style: const TextStyle(
                        color: ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 15))),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                    color: confirmed
                        ? const Color(0xFFE6F4EF)
                        : const Color(0xFFFFF2DD),
                    borderRadius: BorderRadius.circular(30)),
                child: Text(confirmed ? 'CONFIRMED' : 'PAYMENT DUE',
                    style: TextStyle(
                        color: confirmed ? teal : const Color(0xFF986311),
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .5)))
          ]),
          const SizedBox(height: 10),
          _DetailLine(
              icon: Icons.location_on_outlined,
              text: '${booking['location'] ?? ''}'),
          const SizedBox(height: 6),
          _DetailLine(
              icon: Icons.calendar_today_outlined,
              text:
                  '$dateText  ·  ${booking['start_time']}–${booking['end_time']}'),
          if (role != 'advertiser' && booking['advertiser_name'] != null) ...[
            const SizedBox(height: 6),
            _DetailLine(
                icon: Icons.person_outline,
                text: 'Advertiser: ${booking['advertiser_name']}')
          ],
          const SizedBox(height: 10),
          Row(children: [
            if (onStop != null)
              TextButton.icon(
                  onPressed: onStop,
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: const Text('Stop')),
            if (onExtend != null)
              TextButton.icon(
                  onPressed: onExtend,
                  icon: const Icon(Icons.more_time_rounded, size: 18),
                  label: const Text('Extend')),
            const Spacer(),
            Text(money(booking['amount']),
                style: const TextStyle(
                    color: ink, fontWeight: FontWeight.w800, fontSize: 16))
          ]),
        ]));
  }
}

class PairTvDialog extends StatefulWidget {
  const PairTvDialog({super.key});

  @override
  State<PairTvDialog> createState() => _PairTvDialogState();
}

class _PairTvDialogState extends State<PairTvDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  int _activeTab = 0;
  bool _scanning = false;
  final _codeController = TextEditingController();
  String? _codeError;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this, initialIndex: 0);
    _tabs.addListener(() {
      if (_tabs.index != _activeTab) {
        setState(() => _activeTab = _tabs.index);
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _submitCode() {
    final text = _codeController.text.trim();
    if (text.startsWith('smartads://pair')) {
      Navigator.pop(context, text);
      return;
    }
    final code = text.toUpperCase().replaceAll(RegExp(r'\s+'), '');
    if (code.length < 4) {
      setState(() => _codeError = 'Enter the code shown on the TV.');
      return;
    }
    Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Connect a TV Screen'),
        content: SizedBox(
          width: 440,
          height: 380,
          child: Column(
            children: [
              TabBar(
                controller: _tabs,
                tabs: const [
                  Tab(icon: Icon(Icons.keyboard_rounded), text: 'Enter TV code'),
                  Tab(icon: Icon(Icons.qr_code_scanner_rounded), text: 'Scan QR code'),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    // --- Tab 1: Manual code entry (Default - works in simulator) ---
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Enter the short pairing code displayed on the TV screen:',
                            style: TextStyle(
                                color: Color(0xFF4A6066), height: 1.45),
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: _codeController,
                            autofocus: true,
                            textCapitalization: TextCapitalization.characters,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 6),
                            decoration: InputDecoration(
                              labelText: 'TV Pairing Code',
                              errorText: _codeError,
                              hintText: 'A1B2C3D4',
                              hintStyle: const TextStyle(
                                  fontSize: 18,
                                  letterSpacing: 4,
                                  color: Color(0xFFBBCDCF)),
                            ),
                            onSubmitted: (_) => _submitCode(),
                            onChanged: (_) {
                              if (_codeError != null) {
                                setState(() => _codeError = null);
                              }
                            },
                          ),
                          const Spacer(),
                          FilledButton(
                            onPressed: _submitCode,
                            style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(48)),
                            child: const Text('Connect to TV',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                    // --- Tab 2: QR Scanner (Only active when selected) ---
                    _activeTab == 1
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: MobileScanner(
                              errorBuilder: (context, error) => Container(
                                padding: const EdgeInsets.all(20),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E282A),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.videocam_off_rounded,
                                        size: 48, color: Colors.orangeAccent),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Camera unavailable in simulator',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'Use the "Enter TV code" tab to connect using the code on the screen.',
                                      style: TextStyle(
                                          color: Colors.white70, fontSize: 12),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 14),
                                    FilledButton.tonal(
                                      onPressed: () => _tabs.animateTo(0),
                                      child: const Text('Go to Code Entry'),
                                    ),
                                  ],
                                ),
                              ),
                              onDetect: (capture) {
                                if (_scanning) return;
                                final value =
                                    capture.barcodes.firstOrNull?.rawValue;
                                if (value == null ||
                                    !value.startsWith('smartads://pair')) {
                                  return;
                                }
                                setState(() => _scanning = true);
                                Navigator.pop(context, value);
                              },
                            ),
                          )
                        : const SizedBox.shrink(),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
        ],
      );
}

class SelectBillboardDialog extends StatefulWidget {
  const SelectBillboardDialog(
      {super.key, required this.billboards, required this.userCode});
  final List<Map<String, dynamic>> billboards;
  final String userCode;

  @override
  State<SelectBillboardDialog> createState() => _SelectBillboardDialogState();
}

class _SelectBillboardDialogState extends State<SelectBillboardDialog> {
  String? selectedId;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Connect this TV'),
        content: SizedBox(
          width: 430,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.userCode.isNotEmpty) ...[
                const Text('Confirm that this code is visible on the TV:'),
                const SizedBox(height: 8),
                Text(widget.userCode,
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4)),
                const SizedBox(height: 18),
              ],
              DropdownButtonFormField<String>(
                initialValue: selectedId,
                decoration: const InputDecoration(labelText: 'Billboard'),
                items: [
                  for (final board in widget.billboards)
                    DropdownMenuItem(
                        value: '${board['id']}',
                        child: Text('${board['name']} · ${board['location']}')),
                ],
                onChanged: (value) => setState(() => selectedId = value),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: selectedId == null
                  ? null
                  : () => Navigator.pop(
                      context,
                      widget.billboards
                          .firstWhere((item) => '${item['id']}' == selectedId)),
              child: const Text('Connect TV')),
        ],
      );
}

class UserCard extends StatelessWidget {
  const UserCard(
      {super.key,
      required this.account,
      required this.onSuspend,
      required this.onActivate,
      required this.onDelete});
  final Map<String, dynamic> account;
  final VoidCallback onSuspend;
  final VoidCallback onActivate;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) {
    final status = '${account['status']}';
    final role = '${account['role']}';
    final roleLabel = role == 'owner'
        ? 'Billboard owner'
        : role == 'admin'
            ? 'Administrator'
            : 'Advertiser';
    return Container(
        margin: const EdgeInsets.only(bottom: 11),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE8EEEB))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
                backgroundColor: const Color(0xFFE7F3F0),
                foregroundColor: teal,
                child: Text('${account['name']}'.isNotEmpty
                    ? '${account['name']}'.substring(0, 1).toUpperCase()
                    : '?')),
            const SizedBox(width: 11),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('${account['name']}',
                      style: const TextStyle(
                          color: ink, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text('${account['email']}',
                      style: const TextStyle(
                          color: Color(0xFF76878B), fontSize: 12))
                ])),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                    color: status == 'active'
                        ? const Color(0xFFE6F4EF)
                        : const Color(0xFFFFEEEE),
                    borderRadius: BorderRadius.circular(30)),
                child: Text(status.toUpperCase(),
                    style: TextStyle(
                        color:
                            status == 'active' ? teal : const Color(0xFFAA4545),
                        fontSize: 9,
                        fontWeight: FontWeight.w800)))
          ]),
          const SizedBox(height: 11),
          Row(children: [
            Text(roleLabel,
                style: const TextStyle(color: Color(0xFF78888D), fontSize: 11)),
            const Spacer(),
            if (role != 'admin')
              PopupMenuButton<String>(
                  tooltip: 'Manage account',
                  onSelected: (value) {
                    if (value == 'delete') onDelete();
                    if (value == 'suspend') onSuspend();
                    if (value == 'activate') onActivate();
                  },
                  itemBuilder: (_) => [
                        if (status == 'active')
                          const PopupMenuItem(
                              value: 'suspend', child: Text('Suspend account'))
                        else
                          const PopupMenuItem(
                              value: 'activate',
                              child: Text('Restore account')),
                        const PopupMenuItem(
                            value: 'delete', child: Text('Delete account'))
                      ],
                  child: const Icon(Icons.more_horiz, color: Color(0xFF718186)))
          ]),
        ]));
  }
}

class CreateBillboardDialog extends StatefulWidget {
  const CreateBillboardDialog({super.key});
  @override
  State<CreateBillboardDialog> createState() => _CreateBillboardDialogState();
}

class _CreateBillboardDialogState extends State<CreateBillboardDialog> {
  final name = TextEditingController();
  final location = TextEditingController();
  final description = TextEditingController();
  final price = TextEditingController();
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    name.dispose();
    location.dispose();
    description.dispose();
    price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add a billboard',
            style: TextStyle(color: ink, fontWeight: FontWeight.w800)),
        content: Form(
            key: form,
            child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                  controller: name,
                  decoration: const InputDecoration(
                      labelText: 'Billboard name',
                      prefixIcon: Icon(Icons.tv_outlined)),
                  validator: (v) =>
                      (v?.trim().length ?? 0) < 2 ? 'Enter a name.' : null),
              const SizedBox(height: 12),
              TextFormField(
                  controller: location,
                  decoration: const InputDecoration(
                      labelText: 'Location',
                      prefixIcon: Icon(Icons.location_on_outlined)),
                  validator: (v) =>
                      (v?.trim().isEmpty ?? true) ? 'Enter a location.' : null),
              const SizedBox(height: 12),
              TextFormField(
                  controller: price,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Price per hour (FCFA)',
                      prefixIcon: Icon(Icons.payments_outlined)),
                  validator: (v) =>
                      double.tryParse(v ?? '') == null || double.parse(v!) <= 0
                          ? 'Enter a price above zero.'
                          : null),
              const SizedBox(height: 12),
              TextFormField(
                  controller: description,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      labelText: 'Short description (optional)',
                      alignLabelWithHint: true)),
            ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                if (!form.currentState!.validate()) return;
                Navigator.pop(context, {
                  'name': name.text.trim(),
                  'location': location.text.trim(),
                  'description': description.text.trim(),
                  'pricePerHour': double.parse(price.text.trim())
                });
              },
              child: const Text('Add billboard'))
        ],
      );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(
      {required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Expanded(
      child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: const Color(0xFFE8EEEB))),
          child: Row(children: [
            Container(
                width: 37,
                height: 37,
                decoration: BoxDecoration(
                    color: const Color(0xFFE7F3F0),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: teal, size: 20)),
            const SizedBox(width: 11),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value,
                  style: const TextStyle(
                      color: ink, fontSize: 18, fontWeight: FontWeight.w900)),
              Text(label,
                  style: const TextStyle(
                      color: Color(0xFF839194),
                      fontSize: 9,
                      letterSpacing: .8,
                      fontWeight: FontWeight.w700))
            ])
          ])));
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard(
      {required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE8EEEB)),
          borderRadius: BorderRadius.circular(20)),
      child: Column(children: [
        Icon(icon, color: teal, size: 31),
        const SizedBox(height: 10),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: ink, fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 6),
        Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Color(0xFF7C8B8F), fontSize: 12, height: 1.45))
      ]));
}

class _AccountRow extends StatelessWidget {
  const _AccountRow(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, color: teal, size: 19),
        const SizedBox(width: 11),
        Text(label,
            style: const TextStyle(color: Color(0xFF7C8A8E), fontSize: 12)),
        const Spacer(),
        Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: ink, fontWeight: FontWeight.w700, fontSize: 12)))
      ]);
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 14, color: const Color(0xFF809093)),
        const SizedBox(width: 6),
        Expanded(
            child: Text(text,
                style: const TextStyle(color: Color(0xFF718186), fontSize: 12)))
      ]);
}
