class SavedLocation {
  final String id;
  final String label;
  final String? address;
  final String? flat;
  final String? area;
  final double? lat;
  final double? lng;

  const SavedLocation({
    required this.id,
    required this.label,
    this.address,
    this.flat,
    this.area,
    this.lat,
    this.lng,
  });

  factory SavedLocation.fromJson(Map<String, dynamic> json) => SavedLocation(
        id: json['id'] as String,
        label: json['label'] as String? ?? 'Saved',
        address: json['address'] as String?,
        flat: json['flat'] as String?,
        area: json['area'] as String?,
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        if (address != null) 'address': address,
        if (flat != null) 'flat': flat,
        if (area != null) 'area': area,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
      };
}
