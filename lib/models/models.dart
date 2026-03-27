// ── GPS Point ─────────────────────────────────────────────────────────────────
class GpsPoint {
  final double lat;
  final double lng;
  final int    accuracy;
  final bool   manual;

  GpsPoint({required this.lat, required this.lng, required this.accuracy, this.manual = false});

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, 'accuracy': accuracy};

  @override
  String toString() => '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
}

// ── Plate Row (from API or table) ─────────────────────────────────────────────
class PlateRow {
  String fullPlate;
  String vehicleType;
  String streetName;
  String locationDetails;
  String recorderName;
  String recordingDate;
  String gps;

  PlateRow({
    this.fullPlate       = '',
    this.vehicleType     = '',
    this.streetName      = '',
    this.locationDetails = '',
    this.recorderName    = '',
    this.recordingDate   = '',
    this.gps             = '',
  });

  factory PlateRow.fromJson(Map<String, dynamic> j) => PlateRow(
    fullPlate:       _s(j['full_plate'] ?? j['plate']),
    vehicleType:     _s(j['vehicle_type']),
    streetName:      _s(j['street_name']),
    locationDetails: _s(j['location_details']),
    recorderName:    _s(j['recorder_name']),
    recordingDate:   _s(j['recording_date']),
    gps:             _s(j['gps']),
  );

  Map<String, dynamic> toJson() => {
    'full_plate':       fullPlate,
    'vehicle_type':     vehicleType,
    'street_name':      streetName,
    'location_details': locationDetails,
    'recorder_name':    recorderName,
    'recording_date':   recordingDate,
    'gps':              gps,
  };

  static String _s(dynamic v) => v?.toString() ?? '';
}

// ── Queue Item ────────────────────────────────────────────────────────────────
enum QueueStatus { pending, processing, done, error }

class QueueItem {
  final String       id;
  final String       name;
  final String       filePath;
  final List<GpsPoint> gps;
  final int          durationSecs;
  QueueStatus        status;
  String             lastError;

  QueueItem({
    required this.id,
    required this.name,
    required this.filePath,
    required this.gps,
    this.durationSecs = 0,
    this.status       = QueueStatus.pending,
    this.lastError    = '',
  });
}
