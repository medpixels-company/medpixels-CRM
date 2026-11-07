import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || 'https://demo-medical-crm.supabase.co';
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || 'demo-anon-key';

export const isSupabaseConfigured = !!(import.meta.env.VITE_SUPABASE_URL && import.meta.env.VITE_SUPABASE_ANON_KEY);

export const supabase = createClient(supabaseUrl, supabaseAnonKey);

// Initial fallback seed data for instant local preview
export const initialSeedData = {
  organization: {
    name: 'PharmaCare Medical Distribution',
    slug: 'pharmacare',
    plan: 'Enterprise SaaS'
  },
  stats: {
    totalVisitsToday: 18,
    verifiedInGeofence: 15,
    outsideGeofence: 2,
    flaggedMockGps: 1,
    activeRepsCount: 6,
    totalOrdersToday: '124,500 ج.م'
  },
  reps: [
    { id: '1', name: 'د. كريم الشناوي', territory: 'مصر الجديدة والنزهة', activeVisits: 4, status: 'في الميدان' },
    { id: '2', name: 'د. ياسمين عادل', territory: 'مدينة نصر والتجمع', activeVisits: 5, status: 'في الميدان' },
    { id: '3', name: 'د. محمود طارق', territory: 'المعادي وحلوان', activeVisits: 3, status: 'في استراحة' },
    { id: '4', name: 'د. سارة فؤاد', territory: 'الدقي والمهندسين', activeVisits: 6, status: 'مكتمل' }
  ],
  customers: [
    {
      id: 'c1',
      name: 'صيدلية العزبي - روكسي',
      type: 'صيدلية',
      category: 'pharmacy',
      classification: 'Class A',
      address: 'شارع الأهرام، روكسي، مصر الجديدة',
      lat: 30.0886,
      lng: 31.3285,
      geofenceRadius: 150
    },
    {
      id: 'c2',
      name: 'د. أحمد مجدي (استشاري القلب)',
      type: 'طبيب عيادة',
      category: 'doctor',
      classification: 'Class A',
      address: 'برج الأطباء، ميدان تريومف',
      lat: 30.0920,
      lng: 31.3340,
      geofenceRadius: 100
    },
    {
      id: 'c3',
      name: 'مستشفى كليوباترا',
      type: 'مستشفى',
      category: 'hospital',
      classification: 'Class A',
      address: 'شارع كليوباترا، هليوبوليس',
      lat: 30.0901,
      lng: 31.3325,
      geofenceRadius: 250
    },
    {
      id: 'c4',
      name: 'صيدليات سيف - الميرغني',
      type: 'صيدلية',
      category: 'pharmacy',
      classification: 'Class B',
      address: 'شارع الميرغني، مصر الجديدة',
      lat: 30.0945,
      lng: 31.3260,
      geofenceRadius: 150
    },
    {
      id: 'c5',
      name: 'د. هاني شاكر (استشاري العظام)',
      type: 'طبيب عيادة',
      category: 'doctor',
      classification: 'Class B',
      address: 'شارع الحجاز، النزهة',
      lat: 30.1030,
      lng: 31.3410,
      geofenceRadius: 120
    }
  ],
  recentVisits: [
    {
      id: 'v101',
      repName: 'د. كريم الشناوي',
      customerName: 'صيدلية العزبي - روكسي',
      time: '11:15 ص',
      distanceMeters: 42,
      accuracyMeters: 8,
      status: 'valid',
      statusText: 'داخل النطاق (موثقة)',
      samplesCount: 3,
      hasOrder: true,
      orderTotal: '18,400 ج.م'
    },
    {
      id: 'v102',
      repName: 'د. ياسمين عادل',
      customerName: 'د. أحمد مجدي (استشاري القلب)',
      time: '11:40 ص',
      distanceMeters: 75,
      accuracyMeters: 12,
      status: 'valid',
      statusText: 'داخل النطاق (موثقة)',
      samplesCount: 2,
      hasOrder: false,
      orderTotal: '-'
    },
    {
      id: 'v103',
      repName: 'د. محمود طارق',
      customerName: 'مستشفى كليوباترا',
      time: '12:05 م',
      distanceMeters: 380,
      accuracyMeters: 25,
      status: 'outside_geofence',
      statusText: 'خارج النطاق (380 متر)',
      samplesCount: 0,
      hasOrder: false,
      orderTotal: '-'
    },
    {
      id: 'v104',
      repName: 'د. سارة فؤاد',
      customerName: 'صيدليات سيف - الميرغني',
      time: '12:20 م',
      distanceMeters: 0,
      accuracyMeters: 1,
      status: 'flagged',
      statusText: 'تنبيه: محاكاة GPS وهمي',
      samplesCount: 0,
      hasOrder: false,
      orderTotal: '-'
    }
  ]
};
