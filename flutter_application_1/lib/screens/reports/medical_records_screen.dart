import 'package:flutter/material.dart';

class MedicalRecordsScreen extends StatefulWidget {
  const MedicalRecordsScreen({super.key});

  @override
  MedicalRecordsScreenState createState() => MedicalRecordsScreenState();
}

class MedicalRecordsScreenState extends State<MedicalRecordsScreen> {
  final List<PatientRecord> _records = [
    PatientRecord(
      name: 'John Doe',
      id: 'PT-1001',
      age: '35',
      diagnosis: 'Flu',
    ),
    PatientRecord(
      name: 'Jane Smith',
      id: 'PT-1002',
      age: '42',
      diagnosis: 'Diabetes',
    ),
    PatientRecord(
      name: 'Robert Brown',
      id: 'PT-1003',
      age: '58',
      diagnosis: 'Hypertension',
    ),
  ];

  PatientRecord? _selectedRecord;
  final Map<int, bool> _hoverStates = {};

  void _handleDownload(PatientRecord record) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Downloading ${record.name}\'s report...')),
    );
  }

  void _handlePDFConversion() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Generating PDF...')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _selectedRecord = null),
      child: Scaffold(
        backgroundColor: Colors.teal[300],
        appBar: AppBar(
          title: const Text('Medical Records'),
          backgroundColor: Colors.teal[600],
          elevation: 0,
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              _buildLeftPanel(),
              const SizedBox(width: 24),
              _buildRightPanel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeftPanel() {
    return Expanded(
      flex: 4,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSelectedReportSection(),
            const SizedBox(height: 24),
            _buildPatientList(),
            const SizedBox(height: 24),
            _buildActionButton('Convert to PDF', _handlePDFConversion),
            const SizedBox(height: 12),
            _buildActionButton('Download', () {
              if (_selectedRecord != null) _handleDownload(_selectedRecord!);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedReportSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            'Selected Report',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.teal[800],
            ),
          ),
          const SizedBox(height: 8),
          if (_selectedRecord != null)
            Text(
              _selectedRecord!.name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            )
          else
            const Text('No report selected'),
        ],
      ),
    );
  }

  Widget _buildPatientList() {
    return Flexible(
      child: ListView.builder(
        itemCount: _records.length,
        itemBuilder: (context, index) {
          final record = _records[index];
          return MouseRegion(
            onEnter: (_) => setState(() => _hoverStates[index] = true),
            onExit: (_) => setState(() => _hoverStates[index] = false),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _hoverStates[index] ?? false
                    ? Colors.teal[100]
                    : Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(26),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.teal[700],
                  child: const Icon(Icons.person, color: Colors.white),
                ),
                title: Text(record.name),
                subtitle: Text('ID: ${record.id}'),
                onTap: () => setState(() => _selectedRecord = record),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActionButton(String label, VoidCallback? onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.teal[800],
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Text(label),
    );
  }

  Widget _buildRightPanel() {
    return Expanded(
      flex: 6,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Report View',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.teal[800],
              ),
            ),
            const Divider(color: Colors.grey),
            if (_selectedRecord != null)
              Column(
                children: [
                  _buildKeyValueSection(),
                  const SizedBox(height: 16),
                  _buildDetailsSection(),
                ],
              )
            else
              const Center(child: Text('Select a report to view')),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyValueSection() {
    return Column(
      children: [
        _buildKeyValuePair('Name', _selectedRecord!.name),
        _buildKeyValuePair('ID', _selectedRecord!.id),
        _buildKeyValuePair('Age', _selectedRecord!.age),
        _buildKeyValuePair('Diagnosis', _selectedRecord!.diagnosis),
      ],
    );
  }

  Widget _buildKeyValuePair(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(value),
        ],
      ),
    );
  }

  Widget _buildDetailsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDataRow('Visit Date', 'March 23, 2025'),
        _buildDataRow('Doctor', 'Dr. Emily Clark'),
        _buildDataRow('Department', 'General Medicine'),
        const SizedBox(height: 16),
        _buildSectionTitle('Symptoms'),
        const Divider(),
        const Text('Fever, Cough, Body Ache'),
        const SizedBox(height: 8),
        _buildSectionTitle('Prescriptions'),
        const Divider(),
        const Text(
          'Tamiflu 75mg – 2x daily\n'
          'Paracetamol 500mg – as needed',
        ),
        const SizedBox(height: 8),
        _buildSectionTitle('Vitals'),
        const Divider(),
        const Text(
          'Temperature: 101°F\n'
          'Blood Pressure: 120/80 mmHg\n'
          'Heart Rate: 88 bpm',
        ),
        const SizedBox(height: 8),
        _buildSectionTitle("Doctor's Notes"),
        const Divider(),
        const Text(
          'Patient advised to rest for 5 days and increase fluid intake. Return if symptoms persist.',
        ),
      ],
    );
  }

  Widget _buildDataRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(value),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: Colors.teal[600],
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

class PatientRecord {
  final String name;
  final String id;
  final String age;
  final String diagnosis;

  PatientRecord({
    required this.name,
    required this.id,
    required this.age,
    required this.diagnosis,
  });
}
