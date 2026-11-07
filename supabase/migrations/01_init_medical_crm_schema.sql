-- ==============================================================================
-- MEDICAL CRM SAAS - SUPABASE POSTGRESQL + POSTGIS PRODUCTION SCHEMA
-- Multi-Tenant Modular Architecture with Native Row Level Security (RLS)
-- ==============================================================================

-- 1. تفعيل الامتدادات الجغرافية والمفاتيح العشوائية
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";

-- ==============================================================================
-- 2. جدول المنظمات والشركات المستأجرة (Organizations / Tenants)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(150) NOT NULL,
    slug VARCHAR(60) NOT NULL UNIQUE,
    subscription_plan VARCHAR(30) NOT NULL DEFAULT 'enterprise', -- starter, pro, enterprise
    subscription_status VARCHAR(20) NOT NULL DEFAULT 'active', -- active, past_due, canceled
    settings JSONB NOT NULL DEFAULT '{
        "default_geofence_radius": 150,
        "allow_offline_orders": true,
        "max_discount_without_approval": 10.0,
        "require_sample_signature": true
    }'::jsonb,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMPTZ NULL
);

CREATE INDEX IF NOT EXISTS idx_organizations_slug ON public.organizations(slug);

-- ==============================================================================
-- 3. جدول ملفات المستخدمين والمناديب (User Profiles & Roles)
-- مرتبط مع نظام Supabase Auth
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.user_profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
    full_name VARCHAR(150) NOT NULL,
    phone VARCHAR(30) NULL,
    role VARCHAR(30) NOT NULL DEFAULT 'medical_rep', -- 'org_admin', 'sales_manager', 'supervisor', 'medical_rep'
    is_active BOOLEAN NOT NULL DEFAULT true,
    territory_id UUID NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMPTZ NULL
);

CREATE INDEX IF NOT EXISTS idx_profiles_org_role ON public.user_profiles(organization_id, role);

-- ==============================================================================
-- 4. جدول المناطق الجغرافية وخطوط السير (Territories)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.territories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
    name VARCHAR(100) NOT NULL,
    code VARCHAR(30) NOT NULL,
    parent_id UUID NULL REFERENCES public.territories(id) ON DELETE SET NULL,
    boundary GEOMETRY(Polygon, 4326) NULL, -- حدود المنطقة الجغرافية (اختياري)
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMPTZ NULL,
    CONSTRAINT uq_territory_org_code UNIQUE (organization_id, code)
);

CREATE INDEX IF NOT EXISTS idx_territories_org ON public.territories(organization_id);

-- ربط المندوب بالمنطقة بعد إنشاء الجدول
ALTER TABLE public.user_profiles 
    DROP CONSTRAINT IF EXISTS fk_profiles_territory,
    ADD CONSTRAINT fk_profiles_territory 
    FOREIGN KEY (territory_id) REFERENCES public.territories(id) ON DELETE SET NULL;

-- ==============================================================================
-- 5. جدول العملاء: أطباء، عيادات، صيدليات، مستشفيات (Customers / HCPs & HCOs)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
    territory_id UUID NULL REFERENCES public.territories(id) ON DELETE SET NULL,
    name VARCHAR(200) NOT NULL,
    customer_type VARCHAR(50) NOT NULL DEFAULT 'pharmacy', -- 'doctor', 'clinic', 'pharmacy', 'hospital', 'distributor'
    specialty VARCHAR(100) NULL, -- لتصنيف تخصص الطبيب (أطفال، عظام، باطنة...)
    classification VARCHAR(10) NOT NULL DEFAULT 'B', -- 'A', 'B', 'C' حسب الأهمية وحجم المبيعات
    contact_person VARCHAR(100) NULL,
    phone VARCHAR(30) NULL,
    address TEXT NULL,
    -- الإحداثيات المعتمدة للعميل بحسابات PostGIS Geodetic WGS84
    location GEOGRAPHY(Point, 4326) NULL,
    geofence_radius_meters INTEGER NOT NULL DEFAULT 150,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMPTZ NULL
);

CREATE INDEX IF NOT EXISTS idx_customers_org ON public.customers(organization_id);
CREATE INDEX IF NOT EXISTS idx_customers_active ON public.customers(organization_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_customers_location ON public.customers USING GIST(location);

-- ==============================================================================
-- 6. جدول كتالوج المنتجات والأدوية (Products & Medicine Catalog)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
    name VARCHAR(200) NOT NULL,
    code VARCHAR(50) NOT NULL,
    scientific_name VARCHAR(200) NULL,
    category VARCHAR(100) NULL,
    unit_price NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    is_sample_available BOOLEAN NOT NULL DEFAULT true,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMPTZ NULL,
    CONSTRAINT uq_product_org_code UNIQUE (organization_id, code)
);

CREATE INDEX IF NOT EXISTS idx_products_org ON public.products(organization_id);

-- ==============================================================================
-- 7. جدول زيارات المندوبين الميدانية (Visits & GPS Check-in Proof)
-- مع توثيق الحضور ومنع الزيارات الوهمية
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.visits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
    customer_id UUID NOT NULL REFERENCES public.customers(id) ON DELETE RESTRICT,
    rep_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE RESTRICT,
    visit_date DATE NOT NULL DEFAULT CURRENT_DATE,
    status VARCHAR(30) NOT NULL DEFAULT 'planned', -- 'planned', 'in_progress', 'completed', 'cancelled'
    
    -- بيانات تسجيل الحضور الجغرافي (تجمع فقط بلحظة النقر - No continuous tracking)
    checkin_time TIMESTAMPTZ NULL,
    checkout_time TIMESTAMPTZ NULL,
    checkin_location GEOGRAPHY(Point, 4326) NULL,
    gps_accuracy_meters NUMERIC(6, 2) NULL,
    checkin_distance_meters NUMERIC(8, 2) NULL, -- المسافة المحسوبة تلقائياً عن مقر العميل
    
    -- حالة موثوقية الزيارة
    verification_status VARCHAR(30) NOT NULL DEFAULT 'pending', -- 'valid', 'outside_geofence', 'low_accuracy', 'manual_approved', 'flagged'
    is_mock_location_detected BOOLEAN NOT NULL DEFAULT false,
    
    -- مخرجات الزيارة العلمية والترويجية
    visit_notes TEXT NULL,
    doctor_feedback TEXT NULL,
    samples_given JSONB NULL DEFAULT '[]'::jsonb, -- سجل العينات الترويجية التي تم تسليمها
    
    -- مفتاح المزامنة لمنع التكرار (Offline Outbox Pattern)
    idempotency_key VARCHAR(64) NULL,
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMPTZ NULL,
    CONSTRAINT uq_visits_org_idempotency UNIQUE (organization_id, idempotency_key)
);

CREATE INDEX IF NOT EXISTS idx_visits_org_rep_date ON public.visits(organization_id, rep_id, visit_date);
CREATE INDEX IF NOT EXISTS idx_visits_checkin_geo ON public.visits USING GIST(checkin_location);
CREATE INDEX IF NOT EXISTS idx_visits_status ON public.visits(organization_id, verification_status);

-- ==============================================================================
-- 8. جداول أوامر المبيعات (Sales Orders & Items)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.sales_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
    customer_id UUID NOT NULL REFERENCES public.customers(id) ON DELETE RESTRICT,
    rep_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE RESTRICT,
    visit_id UUID NULL REFERENCES public.visits(id) ON DELETE SET NULL,
    order_number VARCHAR(50) NOT NULL,
    order_date DATE NOT NULL DEFAULT CURRENT_DATE,
    subtotal NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    discount_percentage NUMERIC(5, 2) NOT NULL DEFAULT 0.00,
    discount_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    tax_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    total_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    status VARCHAR(30) NOT NULL DEFAULT 'pending_approval', -- 'draft', 'pending_approval', 'approved', 'rejected', 'synced_to_erp'
    approval_notes TEXT NULL,
    approved_by UUID NULL REFERENCES public.user_profiles(id) ON DELETE SET NULL,
    approved_at TIMESTAMPTZ NULL,
    erp_reference_id VARCHAR(100) NULL,
    idempotency_key VARCHAR(64) NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMPTZ NULL,
    CONSTRAINT uq_orders_org_number UNIQUE (organization_id, order_number),
    CONSTRAINT uq_orders_org_idempotency UNIQUE (organization_id, idempotency_key)
);

CREATE INDEX IF NOT EXISTS idx_orders_org_status ON public.sales_orders(organization_id, status);

CREATE TABLE IF NOT EXISTS public.sales_order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
    order_id UUID NOT NULL REFERENCES public.sales_orders(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(12, 2) NOT NULL,
    discount_percentage NUMERIC(5, 2) NOT NULL DEFAULT 0.00,
    total_price NUMERIC(12, 2) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_order_items_order ON public.sales_order_items(order_id);

-- ==============================================================================
-- 9. دالة PostGIS لحساب المسافة والتحقق من السياج الجغرافي تلقائياً
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.fn_process_visit_checkin()
RETURNS TRIGGER AS $$
DECLARE
    v_customer_loc GEOGRAPHY(Point, 4326);
    v_geofence INTEGER;
    v_dist NUMERIC(8, 2);
BEGIN
    -- إذا وجد موقع تسجيل حضور
    IF NEW.checkin_location IS NOT NULL THEN
        -- جلب موقع العميل والسياج المعتمد
        SELECT location, geofence_radius_meters 
        INTO v_customer_loc, v_geofence
        FROM public.customers 
        WHERE id = NEW.customer_id AND organization_id = NEW.organization_id;

        IF v_customer_loc IS NOT NULL THEN
            -- حساب المسافة الجيوديسية الحقيقية بالأمتار
            v_dist := ROUND(ST_Distance(v_customer_loc, NEW.checkin_location)::numeric, 2);
            NEW.checkin_distance_meters := v_dist;

            -- التحقق من الدقة والموقع المزور
            IF NEW.is_mock_location_detected = true THEN
                NEW.verification_status := 'flagged';
            ELSIF NEW.gps_accuracy_meters IS NOT NULL AND NEW.gps_accuracy_meters > 80 THEN
                NEW.verification_status := 'low_accuracy';
            ELSIF v_dist <= v_geofence THEN
                NEW.verification_status := 'valid';
            ELSE
                NEW.verification_status := 'outside_geofence';
            END IF;
        ELSE
            NEW.verification_status := 'valid'; -- في حال لم يكن للعميل إحداثيات محددة مسبقاً
        END IF;
    END IF;

    NEW.updated_at := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_visit_checkin ON public.visits;
CREATE TRIGGER trg_visit_checkin
    BEFORE INSERT OR UPDATE OF checkin_location, is_mock_location_detected, gps_accuracy_meters
    ON public.visits
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_process_visit_checkin();

-- ==============================================================================
-- 10. جدول إدارة إصدارات التطبيق والتحديث التلقائي للـ APK (App Releases & In-App OTA)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.app_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    platform VARCHAR(20) NOT NULL DEFAULT 'android',
    version_name VARCHAR(20) NOT NULL, -- مثل '1.0.0'
    version_code INTEGER NOT NULL,     -- رقم الإصدار العددي للمقارنة مثل 100
    apk_url TEXT NOT NULL,             -- رابط تحميل ملف الـ APK المباشر
    release_notes TEXT NULL,           -- ملخص التحديث والمزايا الجديدة
    is_mandatory BOOLEAN NOT NULL DEFAULT false, -- هل التحديث إجباري لمنع الاستمرار بالنسخة القديمة؟
    min_supported_version_code INTEGER NOT NULL DEFAULT 100,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- لا نحتاج RLS على جدول الإصدارات ليتمكن التطبيق من قراءته قبل تسجيل الدخول
ALTER TABLE public.app_versions ENABLE ROW LEVEL SECURITY;
CREATE POLICY rls_app_versions_read ON public.app_versions FOR SELECT USING (true);

-- ==============================================================================
-- 11. دالة استخراج معرف المنظمة الحالية من المستخدم المصادق (RLS Helper)
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.get_current_org_id()
RETURNS UUID AS $$
    SELECT organization_id 
    FROM public.user_profiles 
    WHERE id = auth.uid() 
    LIMIT 1;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- ==============================================================================
-- 11. تفعيل سياسات Row Level Security (RLS) الصارمة
-- عزل مطلق ومضمون للبيانات بين الشركات
-- ==============================================================================

-- تفعيل RLS على كل الجداول
ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.territories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_order_items ENABLE ROW LEVEL SECURITY;

-- فرض الـ RLS حتى على مالكي الجداول لمنع أي تجاوز غير مقصود
ALTER TABLE public.customers FORCE ROW LEVEL SECURITY;
ALTER TABLE public.visits FORCE ROW LEVEL SECURITY;
ALTER TABLE public.sales_orders FORCE ROW LEVEL SECURITY;
ALTER TABLE public.sales_order_items FORCE ROW LEVEL SECURITY;

-- سياسة ملف المستخدم
DROP POLICY IF EXISTS rls_profiles_policy ON public.user_profiles;
CREATE POLICY rls_profiles_policy ON public.user_profiles
    FOR ALL
    USING (id = auth.uid() OR organization_id = public.get_current_org_id())
    WITH CHECK (organization_id = public.get_current_org_id());

-- سياسة العملاء (Customers)
DROP POLICY IF EXISTS rls_customers_policy ON public.customers;
CREATE POLICY rls_customers_policy ON public.customers
    FOR ALL
    USING (organization_id = public.get_current_org_id())
    WITH CHECK (organization_id = public.get_current_org_id());

-- سياسة المنتجات (Products)
DROP POLICY IF EXISTS rls_products_policy ON public.products;
CREATE POLICY rls_products_policy ON public.products
    FOR ALL
    USING (organization_id = public.get_current_org_id())
    WITH CHECK (organization_id = public.get_current_org_id());

-- سياسة الزيارات (Visits)
DROP POLICY IF EXISTS rls_visits_policy ON public.visits;
CREATE POLICY rls_visits_policy ON public.visits
    FOR ALL
    USING (organization_id = public.get_current_org_id())
    WITH CHECK (organization_id = public.get_current_org_id());

-- سياسة أوامر البيع (Sales Orders)
DROP POLICY IF EXISTS rls_orders_policy ON public.sales_orders;
CREATE POLICY rls_orders_policy ON public.sales_orders
    FOR ALL
    USING (organization_id = public.get_current_org_id())
    WITH CHECK (organization_id = public.get_current_org_id());

DROP POLICY IF EXISTS rls_order_items_policy ON public.sales_order_items;
CREATE POLICY rls_order_items_policy ON public.sales_order_items
    FOR ALL
    USING (organization_id = public.get_current_org_id())
    WITH CHECK (organization_id = public.get_current_org_id());

-- سياسة المناطق (Territories)
DROP POLICY IF EXISTS rls_territories_policy ON public.territories;
CREATE POLICY rls_territories_policy ON public.territories
    FOR ALL
    USING (organization_id = public.get_current_org_id())
    WITH CHECK (organization_id = public.get_current_org_id());

-- ==============================================================================
-- 12. بيانات تجريبية مبدئية للاختبار الفوري (Seed Data)
-- ==============================================================================
DO $$
DECLARE
    v_demo_org_id UUID := '11111111-1111-1111-1111-111111111111';
    v_cairo_terr_id UUID := '22222222-2222-2222-2222-222222222222';
BEGIN
    -- إدراج شركة تجريبية
    INSERT INTO public.organizations (id, name, slug, subscription_plan, subscription_status)
    VALUES (v_demo_org_id, 'PharmaCare Medical Distribution', 'pharmacare', 'enterprise', 'active')
    ON CONFLICT (id) DO NOTHING;

    -- إدراج منطقة جغرافية
    INSERT INTO public.territories (id, organization_id, name, code)
    VALUES (v_cairo_terr_id, v_demo_org_id, 'Cairo Central & Heliopolis', 'CAI-01')
    ON CONFLICT (id) DO NOTHING;

    -- إدراج عملاء (صيدليات ومستشفيات مع إحداثيات GPS حقيقية في القاهرة)
    INSERT INTO public.customers (id, organization_id, territory_id, name, customer_type, specialty, classification, location, geofence_radius_meters, address)
    VALUES 
    (
        '33333333-3333-3333-3333-333333333331',
        v_demo_org_id,
        v_cairo_terr_id,
        'صيدلية العزبي - فرع مصر الجديدة',
        'pharmacy',
        'Retail Pharmacy',
        'A',
        ST_SetSRID(ST_MakePoint(31.3285, 30.0886), 4326)::geography,
        150,
        'شارع الأهرام، روكسي، مصر الجديدة'
    ),
    (
        '33333333-3333-3333-3333-333333333332',
        v_demo_org_id,
        v_cairo_terr_id,
        'د. أحمد مجدي - استشاري أمراض القلب',
        'doctor',
        'Cardiology',
        'A',
        ST_SetSRID(ST_MakePoint(31.3340, 30.0920), 4326)::geography,
        100,
        'برج الأطباء، ميدان تريومف'
    ),
    (
        '33333333-3333-3333-3333-333333333333',
        v_demo_org_id,
        v_cairo_terr_id,
        'مستشفى كليوباترا',
        'hospital',
        'General Hospital',
        'A',
        ST_SetSRID(ST_MakePoint(31.3325, 30.0901), 4326)::geography,
        250,
        'شارع كليوباترا، مصر الجديدة'
    )
    ON CONFLICT (id) DO NOTHING;

    -- إدراج أدوية ومنتجات طبية
    INSERT INTO public.products (organization_id, name, code, scientific_name, category, unit_price, is_sample_available)
    VALUES
    (v_demo_org_id, 'CardioProtect 50mg Tablets', 'MED-CP50', 'Atenolol 50mg', 'Cardiovascular', 85.50, true),
    (v_demo_org_id, 'GlucoFree 500mg Film-Coated', 'MED-GF500', 'Metformin HCl 500mg', 'Endocrinology', 45.00, true),
    (v_demo_org_id, 'NeuroMax B-Complex Ampoules', 'MED-NM-AMP', 'Vitamin B1, B6, B12', 'Neurology', 120.00, true),
    (v_demo_org_id, 'PanCure 1g IV Infusion', 'MED-PC1G', 'Paracetamol 10mg/ml', 'Analgesics', 65.00, false)
    ON CONFLICT DO NOTHING;

    -- إدراج أول إصدار للتطبيق لتشغيل نظام التحديث الذاتي
    INSERT INTO public.app_versions (platform, version_name, version_code, apk_url, release_notes, is_mandatory)
    VALUES ('android', '1.0.0', 100, 'https://example.com/downloads/medical-crm-v1.0.0.apk', 'الإصدار المبدئي لنظام متابعة المناديب والزيارات', false)
    ON CONFLICT DO NOTHING;

END $$;
