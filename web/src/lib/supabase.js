import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || 'https://demo-medical-crm.supabase.co';
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || 'demo-anon-key';

export const isSupabaseConfigured = !!(import.meta.env.VITE_SUPABASE_URL && import.meta.env.VITE_SUPABASE_ANON_KEY);
export const supabase = createClient(supabaseUrl, supabaseAnonKey);

export const blendedDataset = {
  organization: {
    name: 'PharmaCare Medical Distribution',
    slug: 'pharmacare',
    plan: 'Enterprise SaaS'
  },
  products: [
    { id: 'p1', name: 'CardioProtect 50mg (أقراص قلب وضغط)', price: 85.50, sampleAvailable: true, category: 'أمراض قلب' },
    { id: 'p2', name: 'GlucoFree 500mg (علاج سكر ممتد المفعول)', price: 45.00, sampleAvailable: true, category: 'غدد وسكر' },
    { id: 'p3', name: 'NeuroMax B-Complex (أمبولات فيتامين للأعصاب)', price: 120.00, sampleAvailable: true, category: 'أعصاب' },
    { id: 'p4', name: 'PanCure 1g IV (مسكن وريدي للمستشفيات)', price: 65.00, sampleAvailable: false, category: 'مسكنات وطوارئ' }
  ],
  customers: [
    {
      id: 'c1',
      name: 'صيدلية العزبي - فرع روكسي',
      type: 'صيدلية',
      category: 'pharmacy',
      classification: 'Class A',
      address: 'شارع الأهرام، روكسي، مصر الجديدة',
      lat: 30.0886,
      lng: 31.3285,
      geofenceRadius: 150,
      doctorSpecialty: null,
      repAssigned: 'د. كريم الشناوي'
    },
    {
      id: 'c2',
      name: 'د. أحمد مجدي (استشاري القلب والأوعية)',
      type: 'طبيب عيادة',
      category: 'doctor',
      classification: 'Class A',
      address: 'برج الأطباء، ميدان تريومف',
      lat: 30.0920,
      lng: 31.3340,
      geofenceRadius: 100,
      doctorSpecialty: 'Cardiology',
      repAssigned: 'د. ياسمين عادل'
    },
    {
      id: 'c3',
      name: 'مستشفى كليوباترا - قسم الصيدلة الداخلية',
      type: 'مستشفى',
      category: 'hospital',
      classification: 'Class A',
      address: 'شارع كليوباترا، هليوبوليس',
      lat: 30.0901,
      lng: 31.3325,
      geofenceRadius: 250,
      doctorSpecialty: 'Hospital Purchasing',
      repAssigned: 'د. كريم الشناوي'
    },
    {
      id: 'c4',
      name: 'صيدليات سيف - فرع الميرغني',
      type: 'صيدلية',
      category: 'pharmacy',
      classification: 'Class B',
      address: 'شارع الميرغني، مصر الجديدة',
      lat: 30.0945,
      lng: 31.3260,
      geofenceRadius: 150,
      doctorSpecialty: null,
      repAssigned: 'د. سارة فؤاد'
    },
    {
      id: 'c5',
      name: 'د. هاني شاكر (استشاري جراحة العظام والمفاصل)',
      type: 'طبيب عيادة',
      category: 'doctor',
      classification: 'Class B',
      address: 'شارع الحجاز، النزهة الجديدة',
      lat: 30.1030,
      lng: 31.3410,
      geofenceRadius: 120,
      doctorSpecialty: 'Orthopedics',
      repAssigned: 'د. محمود طارق'
    }
  ],
  initialVisits: [
    {
      id: 'v-101',
      repName: 'د. كريم الشناوي',
      customerName: 'صيدلية العزبي - فرع روكسي',
      time: '10:30 ص',
      distanceMeters: 42,
      accuracyMeters: 8,
      status: 'valid',
      statusText: 'داخل النطاق (حضور موثق)',
      samplesCount: 4,
      detailingNotes: 'اهتمام بطلب كميات إضافية من NeuroMax للشتاء',
      hasOrder: true,
      orderTotal: '18,400 ج.م',
      syncOrigin: 'Synced from Outbox'
    },
    {
      id: 'v-102',
      repName: 'د. ياسمين عادل',
      customerName: 'د. أحمد مجدي (استشاري القلب)',
      time: '11:15 ص',
      distanceMeters: 65,
      accuracyMeters: 12,
      status: 'valid',
      statusText: 'داخل النطاق (حضور موثق)',
      samplesCount: 2,
      detailingNotes: 'مناقشة دراسات الأمان لـ CardioProtect 50mg',
      hasOrder: false,
      orderTotal: '-',
      syncOrigin: 'Live Check-in'
    },
    {
      id: 'v-103',
      repName: 'د. محمود طارق',
      customerName: 'د. هاني شاكر (استشاري جراحة العظام)',
      time: '12:05 م',
      distanceMeters: 380,
      accuracyMeters: 25,
      status: 'outside_geofence',
      statusText: 'خارج السياج (380 متر)',
      samplesCount: 0,
      detailingNotes: 'المندوب سجل الزيارة من الكافيه المجاور للعيادة',
      hasOrder: false,
      orderTotal: '-',
      syncOrigin: 'Flagged by PostGIS'
    },
    {
      id: 'v-104',
      repName: 'د. سارة فؤاد',
      customerName: 'صيدليات سيف - فرع الميرغني',
      time: '12:45 م',
      distanceMeters: 0,
      accuracyMeters: 1,
      status: 'flagged',
      statusText: 'تحذير: تطبيق GPS زائف (Fake Location)',
      samplesCount: 0,
      detailingNotes: 'تم كشف استخدام Mock Location Provider وحجب الاعتماد',
      hasOrder: false,
      orderTotal: '-',
      syncOrigin: 'Security Violation'
    }
  ]
};
