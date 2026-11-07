<script>
  import { onMount } from 'svelte';
  import { initialSeedData, isSupabaseConfigured } from './lib/supabase.js';

  let currentTab = $state('map'); // 'map', 'visits', 'customers', 'orders', 'download'
  let selectedCustomer = $state(null);
  let mapInstance = null;
  let mapElement = null;

  const data = initialSeedData;

  onMount(() => {
    initLeafletMap();
  });

  function initLeafletMap() {
    if (typeof window === 'undefined' || !window.L) {
      // Dynamic import/wait if needed
      setTimeout(initLeafletMap, 200);
      return;
    }

    const L = window.L;
    if (mapInstance) {
      mapInstance.remove();
    }

    if (!document.getElementById('leaflet-map')) return;

    // Center on Cairo / Heliopolis
    mapInstance = L.map('leaflet-map').setView([30.0920, 31.3320], 14);

    // Dark Tile Layer (CartoDB Dark Matter)
    L.tileLayer('https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png', {
      attribution: '&copy; OpenStreetMap &copy; CARTO',
      subdomains: 'abcd',
      maxZoom: 19
    }).addTo(mapInstance);

    // Add Customers and their Geofences
    data.customers.forEach(cust => {
      // Circle representing geofence
      const circle = L.circle([cust.lat, cust.lng], {
        color: cust.category === 'hospital' ? '#3b82f6' : cust.category === 'doctor' ? '#10b981' : '#f59e0b',
        fillColor: cust.category === 'hospital' ? '#3b82f6' : cust.category === 'doctor' ? '#10b981' : '#f59e0b',
        fillOpacity: 0.15,
        weight: 1.5,
        radius: cust.geofenceRadius
      }).addTo(mapInstance);

      // Marker for Customer
      const marker = L.marker([cust.lat, cust.lng]).addTo(mapInstance);
      marker.bindPopup(`
        <div style="font-family: 'Cairo', sans-serif; text-align: right; min-width: 180px;">
          <h4 style="font-weight: 700; margin-bottom: 4px; color: #1e293b;">${cust.name}</h4>
          <p style="font-size: 12px; color: #64748b; margin-bottom: 4px;">${cust.address}</p>
          <span style="display:inline-block; font-size:11px; padding:2px 8px; border-radius:12px; background:#e0f2fe; color:#0369a1; font-weight:600;">
            نطاق الحضور: ${cust.geofenceRadius} متر
          </span>
        </div>
      `);

      marker.on('click', () => {
        selectedCustomer = cust;
      });
    });

    // Invalidate size on tab switch
    setTimeout(() => {
      if (mapInstance) mapInstance.invalidateSize();
    }, 300);
  }

  function handleTabChange(tab) {
    currentTab = tab;
    if (tab === 'map') {
      setTimeout(initLeafletMap, 100);
    }
  }

  function approveVisit(visitId) {
    const v = data.recentVisits.find(item => item.id === visitId);
    if (v) {
      v.status = 'valid';
      v.statusText = 'تم الاعتماد اليدوي';
    }
  }
</script>

<div class="min-h-screen bg-[#090d16] text-slate-100 flex flex-col font-['Cairo']">
  <!-- Top Navigation Bar -->
  <header class="border-b border-slate-800 bg-[#0f172a]/90 backdrop-blur sticky top-0 z-50 px-6 py-3.5 flex items-center justify-between">
    <div class="flex items-center gap-4">
      <div class="w-10 h-10 rounded-xl bg-gradient-to-tr from-blue-600 to-teal-400 flex items-center justify-center shadow-lg shadow-blue-500/20 font-black text-xl text-white">
        M
      </div>
      <div>
        <div class="flex items-center gap-2">
          <h1 class="font-bold text-lg text-white leading-tight">{data.organization.name}</h1>
          <span class="text-[11px] px-2 py-0.5 rounded-full bg-blue-500/10 text-blue-400 border border-blue-500/20 font-semibold">
            {data.organization.plan}
          </span>
        </div>
        <p class="text-xs text-slate-400">منظومة متابعة المبيعات الميدانية والتحقق الجغرافي (Medical FFA)</p>
      </div>
    </div>

    <!-- Navigation Tabs -->
    <nav class="flex items-center gap-1.5 bg-slate-900/90 p-1 rounded-xl border border-slate-800">
      <button 
        onclick={() => handleTabChange('map')}
        class="px-4 py-2 rounded-lg text-sm font-semibold transition-all cursor-pointer flex items-center gap-2 {currentTab === 'map' ? 'bg-blue-600 text-white shadow-md' : 'text-slate-400 hover:text-white hover:bg-slate-800/60'}">
        <span>🗺️</span> الخريطة الميدانية
      </button>

      <button 
        onclick={() => handleTabChange('visits')}
        class="px-4 py-2 rounded-lg text-sm font-semibold transition-all cursor-pointer flex items-center gap-2 {currentTab === 'visits' ? 'bg-blue-600 text-white shadow-md' : 'text-slate-400 hover:text-white hover:bg-slate-800/60'}">
        <span>📋</span> الزيارات والـ GPS
      </button>

      <button 
        onclick={() => handleTabChange('customers')}
        class="px-4 py-2 rounded-lg text-sm font-semibold transition-all cursor-pointer flex items-center gap-2 {currentTab === 'customers' ? 'bg-blue-600 text-white shadow-md' : 'text-slate-400 hover:text-white hover:bg-slate-800/60'}">
        <span>🏥</span> الأطباء والمراكز
      </button>

      <button 
        onclick={() => handleTabChange('download')}
        class="px-4 py-2 rounded-lg text-sm font-semibold transition-all cursor-pointer flex items-center gap-2 {currentTab === 'download' ? 'bg-emerald-600 text-white shadow-md shadow-emerald-500/20' : 'text-emerald-400 hover:text-emerald-300 hover:bg-emerald-950/40'}">
        <span>📱</span> تحميل APK المندوب
      </button>
    </nav>

    <!-- Supabase Status Badge -->
    <div class="flex items-center gap-3">
      <div class="flex items-center gap-2 text-xs bg-slate-900 border border-slate-800 px-3 py-1.5 rounded-lg">
        <span class="w-2.5 h-2.5 rounded-full {isSupabaseConfigured ? 'bg-emerald-500 animate-pulse' : 'bg-amber-400'}"></span>
        <span class="text-slate-300 font-medium">{isSupabaseConfigured ? 'Supabase متصل' : 'بيئة تجريبية جاهزة'}</span>
      </div>
    </div>
  </header>

  <!-- Main Body Content -->
  <main class="flex-1 p-6 max-w-7xl w-full mx-auto space-y-6">

    <!-- KPI Summary Cards -->
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-4">
      <div class="glass-panel p-4 rounded-xl border border-slate-800/80 bg-slate-900/60">
        <div class="text-xs text-slate-400 mb-1 font-medium">إجمالي زيارات اليوم</div>
        <div class="text-2xl font-black text-white">{data.stats.totalVisitsToday}</div>
        <div class="text-[11px] text-blue-400 mt-1">معدل الإنجاز 85%</div>
      </div>

      <div class="glass-panel p-4 rounded-xl border border-slate-800/80 bg-slate-900/60">
        <div class="text-xs text-slate-400 mb-1 font-medium">حضور موثق (داخل السياج)</div>
        <div class="text-2xl font-black text-emerald-400">{data.stats.verifiedInGeofence}</div>
        <div class="text-[11px] text-emerald-500 mt-1">دقة GPS أقل من 15 متر</div>
      </div>

      <div class="glass-panel p-4 rounded-xl border border-slate-800/80 bg-slate-900/60">
        <div class="text-xs text-slate-400 mb-1 font-medium">خارج النطاق الجغرافي</div>
        <div class="text-2xl font-black text-amber-400">{data.stats.outsideGeofence}</div>
        <div class="text-[11px] text-amber-500 mt-1">تحتاج مراجعة المشرف</div>
      </div>

      <div class="glass-panel p-4 rounded-xl border border-slate-800/80 bg-slate-900/60">
        <div class="text-xs text-slate-400 mb-1 font-medium">تنبيهات GPS زائف (Mock)</div>
        <div class="text-2xl font-black text-rose-500">{data.stats.flaggedMockGps}</div>
        <div class="text-[11px] text-rose-400 mt-1">تم حجب الاعتماد تلقائياً</div>
      </div>

      <div class="glass-panel p-4 rounded-xl border border-slate-800/80 bg-slate-900/60">
        <div class="text-xs text-slate-400 mb-1 font-medium">طلبيات البيع المسجلة</div>
        <div class="text-2xl font-black text-teal-300">{data.stats.totalOrdersToday}</div>
        <div class="text-[11px] text-teal-400 mt-1">جاهزة للترحيل للـ ERP</div>
      </div>
    </div>

    <!-- TAB 1: LIVE MAP -->
    {#if currentTab === 'map'}
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <!-- Map Canvas -->
        <div class="lg:col-span-2 glass-panel p-4 rounded-2xl border border-slate-800/80 bg-slate-900/60 flex flex-col h-[560px]">
          <div class="flex items-center justify-between mb-3 px-1">
            <div class="flex items-center gap-2">
              <span class="text-lg">🗺️</span>
              <h3 class="font-bold text-white text-base">خريطة المناديب والتغطية الطبية الحية (القاهرة الكبرى)</h3>
            </div>
            <div class="flex items-center gap-3 text-xs">
              <span class="flex items-center gap-1.5 text-blue-400"><span class="w-2 h-2 rounded-full bg-blue-500"></span> مستشفيات</span>
              <span class="flex items-center gap-1.5 text-emerald-400"><span class="w-2 h-2 rounded-full bg-emerald-500"></span> أطباء</span>
              <span class="flex items-center gap-1.5 text-amber-400"><span class="w-2 h-2 rounded-full bg-amber-500"></span> صيدليات</span>
            </div>
          </div>
          <!-- The Leaflet container -->
          <div id="leaflet-map" class="flex-1 w-full rounded-xl overflow-hidden shadow-inner border border-slate-800"></div>
        </div>

        <!-- Reps & Customers Sidebar -->
        <div class="space-y-4">
          <div class="glass-panel p-4 rounded-2xl border border-slate-800/80 bg-slate-900/60">
            <h3 class="font-bold text-white mb-3 text-sm flex items-center justify-between">
              <span>المناديب الميدانيين النشطين</span>
              <span class="text-xs bg-slate-800 text-blue-400 px-2 py-0.5 rounded-full">{data.reps.length} مناديب</span>
            </h3>
            <div class="space-y-2.5">
              {#each data.reps as rep}
                <div class="p-3 rounded-xl bg-slate-800/40 border border-slate-800/60 hover:border-slate-700 transition flex items-center justify-between">
                  <div>
                    <div class="font-bold text-sm text-slate-100">{rep.name}</div>
                    <div class="text-xs text-slate-400 mt-0.5">{rep.territory}</div>
                  </div>
                  <div class="text-left">
                    <span class="text-[11px] px-2 py-0.5 rounded-md font-medium {rep.status === 'في الميدان' ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20' : 'bg-slate-700/50 text-slate-300'}">
                      {rep.status}
                    </span>
                    <div class="text-[11px] text-slate-400 mt-1 font-mono">{rep.activeVisits} زيارات</div>
                  </div>
                </div>
              {/each}
            </div>
          </div>

          <!-- Privacy Notice Alert -->
          <div class="p-4 rounded-2xl bg-blue-950/20 border border-blue-800/30 text-xs text-blue-300/90 leading-relaxed">
            <div class="font-bold text-blue-400 mb-1 flex items-center gap-1.5">
              <span>🛡️</span> خصوصية المندوب وترشيد البطارية
            </div>
            النظام لا يقوم بتتبع المندوب في الخلفية (No continuous background GPS). يتم تسجيل إحداثية الـ GPS فقط لحظة قيام المندوب بالضغط على زر "تسجيل الزيارة" أمام مقر العميل.
          </div>
        </div>
      </div>
    {/if}

    <!-- TAB 2: VISITS & PROOF OF PRESENCE -->
    {#if currentTab === 'visits'}
      <div class="glass-panel p-6 rounded-2xl border border-slate-800/80 bg-slate-900/60">
        <div class="flex items-center justify-between mb-4">
          <div>
            <h3 class="font-bold text-lg text-white">سجل الزيارات وإشارات التحقق الجغرافي (GPS Proof of Presence)</h3>
            <p class="text-xs text-slate-400 mt-1">يتم قياس المسافة الحقيقية بالأمتار لحظة وصول المندوب لبوابة المركز أو الصيدلية عبر PostGIS</p>
          </div>
          <button class="text-xs bg-slate-800 hover:bg-slate-700 px-3 py-1.5 rounded-lg border border-slate-700 text-slate-200 transition">
            تصدير تقرير Excel
          </button>
        </div>

        <div class="overflow-x-auto">
          <table class="w-full text-right text-sm">
            <thead class="bg-slate-800/60 text-slate-400 text-xs uppercase border-b border-slate-700">
              <tr>
                <th class="py-3 px-4">المندوب</th>
                <th class="py-3 px-4">العميل / المركز</th>
                <th class="py-3 px-4">وقت الحضور</th>
                <th class="py-3 px-4">المسافة عن البوابة</th>
                <th class="py-3 px-4">دقة الـ GPS</th>
                <th class="py-3 px-4">حالة التحقق</th>
                <th class="py-3 px-4">طلبية بيع</th>
                <th class="py-3 px-4 text-center">إجراء المشرف</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-slate-800/60">
              {#each data.recentVisits as v}
                <tr class="hover:bg-slate-800/30 transition">
                  <td class="py-3 px-4 font-bold text-white">{v.repName}</td>
                  <td class="py-3 px-4 text-slate-200">{v.customerName}</td>
                  <td class="py-3 px-4 font-mono text-xs text-slate-400">{v.time}</td>
                  <td class="py-3 px-4 font-mono text-xs">
                    <span class="{v.distanceMeters <= 150 ? 'text-emerald-400 font-bold' : 'text-amber-400 font-bold'}">
                      {v.distanceMeters} متر
                    </span>
                  </td>
                  <td class="py-3 px-4 font-mono text-xs text-slate-400">±{v.accuracyMeters}m</td>
                  <td class="py-3 px-4">
                    {#if v.status === 'valid'}
                      <span class="px-2.5 py-1 rounded-full text-xs font-semibold badge-success">
                        {v.statusText}
                      </span>
                    {:else if v.status === 'outside_geofence'}
                      <span class="px-2.5 py-1 rounded-full text-xs font-semibold badge-warning">
                        {v.statusText}
                      </span>
                    {:else}
                      <span class="px-2.5 py-1 rounded-full text-xs font-semibold badge-danger">
                        {v.statusText}
                      </span>
                    {/if}
                  </td>
                  <td class="py-3 px-4">
                    {#if v.hasOrder}
                      <span class="font-bold text-teal-400 text-xs font-mono">{v.orderTotal}</span>
                    {:else}
                      <span class="text-slate-500 text-xs">-</span>
                    {/if}
                  </td>
                  <td class="py-3 px-4 text-center">
                    {#if v.status !== 'valid'}
                      <button 
                        onclick={() => approveVisit(v.id)}
                        class="px-2.5 py-1 rounded-lg text-xs bg-blue-600/20 text-blue-400 border border-blue-500/30 hover:bg-blue-600 hover:text-white transition">
                        اعتماد يدوي
                      </button>
                    {:else}
                      <span class="text-xs text-slate-500">معتمد ✓</span>
                    {/if}
                  </td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      </div>
    {/if}

    <!-- TAB 3: CUSTOMERS DIRECTORY -->
    {#if currentTab === 'customers'}
      <div class="glass-panel p-6 rounded-2xl border border-slate-800/80 bg-slate-900/60">
        <div class="flex items-center justify-between mb-4">
          <div>
            <h3 class="font-bold text-lg text-white">دليل الأطباء والصيدليات والمستشفيات (HCPs & HCOs)</h3>
            <p class="text-xs text-slate-400 mt-1">كافة المراكز الطبية مزودة بنطاق إثبات الحضور الجغرافي (Geofence Radius)</p>
          </div>
          <button class="text-xs bg-blue-600 hover:bg-blue-500 text-white font-bold px-3 py-2 rounded-lg transition flex items-center gap-1.5 shadow-lg shadow-blue-600/20">
            <span>+</span> إضافة عميل جديد
          </button>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {#each data.customers as cust}
            <div class="p-4 rounded-xl bg-slate-800/40 border border-slate-800/80 hover:border-slate-700 transition">
              <div class="flex items-start justify-between">
                <div>
                  <h4 class="font-bold text-white text-sm">{cust.name}</h4>
                  <span class="text-[11px] px-2 py-0.5 rounded-md font-semibold mt-1 inline-block {cust.category === 'hospital' ? 'bg-blue-500/10 text-blue-400' : cust.category === 'doctor' ? 'bg-emerald-500/10 text-emerald-400' : 'bg-amber-500/10 text-amber-400'}">
                    {cust.type} • {cust.classification}
                  </span>
                </div>
                <span class="text-xs font-mono text-slate-400 bg-slate-800 px-2 py-1 rounded">
                  {cust.geofenceRadius}م سياج
                </span>
              </div>
              <p class="text-xs text-slate-400 mt-2 flex items-center gap-1">
                <span>📍</span> {cust.address}
              </p>
              <div class="mt-3 pt-3 border-t border-slate-800/60 flex items-center justify-between text-xs">
                <span class="text-slate-500 font-mono">GPS: {cust.lat.toFixed(4)}, {cust.lng.toFixed(4)}</span>
                <button class="text-blue-400 hover:underline">تعديل الإحداثيات</button>
              </div>
            </div>
          {/each}
        </div>
      </div>
    {/if}

    <!-- TAB 4: MOBILE APK DOWNLOAD HUB -->
    {#if currentTab === 'download'}
      <div class="max-w-2xl mx-auto glass-panel p-8 rounded-3xl border border-slate-800/80 bg-slate-900/80 text-center space-y-6">
        <div class="w-16 h-16 mx-auto rounded-2xl bg-gradient-to-tr from-emerald-500 to-teal-400 flex items-center justify-center text-3xl shadow-xl shadow-emerald-500/20">
          📱
        </div>

        <div>
          <h2 class="text-2xl font-black text-white">تطبيق المندوب الميداني (Android APK)</h2>
          <p class="text-sm text-slate-400 mt-2">
            نسخة الأندرويد المخصصة لفرق المبيعات الميدانية. تعمل بدون إنترنت بالكامل (Offline-First) مع التحقق الذاتي من الحضور الجغرافي.
          </p>
        </div>

        <!-- Release Info Card -->
        <div class="p-4 rounded-2xl bg-slate-800/50 border border-slate-700/60 text-right flex items-center justify-between">
          <div>
            <div class="text-xs text-slate-400">الإصدار الإنتاجي الأحدث</div>
            <div class="font-bold text-white text-base">v1.0.0 (Build 100)</div>
          </div>
          <div class="text-left">
            <span class="px-2.5 py-1 rounded-full text-xs font-semibold badge-success">
              يدعم التحديث الذاتي OTA
            </span>
            <div class="text-xs text-slate-400 mt-1">الحجم: ~28 MB</div>
          </div>
        </div>

        <!-- Download Buttons & QR Code -->
        <div class="flex flex-col sm:flex-row items-center justify-center gap-6 pt-2">
          <!-- QR Code box -->
          <div class="p-3 bg-white rounded-2xl shadow-lg border border-slate-200">
            <!-- Simple QR SVG Placeholder for demo -->
            <svg class="w-36 h-36" viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
              <rect width="100" height="100" fill="white"/>
              <!-- Corner Finder patterns -->
              <rect x="10" y="10" width="24" height="24" rx="3" fill="#0f172a"/>
              <rect x="14" y="14" width="16" height="16" rx="2" fill="white"/>
              <rect x="18" y="18" width="8" height="8" rx="1" fill="#0f172a"/>

              <rect x="66" y="10" width="24" height="24" rx="3" fill="#0f172a"/>
              <rect x="70" y="14" width="16" height="16" rx="2" fill="white"/>
              <rect x="74" y="18" width="8" height="8" rx="1" fill="#0f172a"/>

              <rect x="10" y="66" width="24" height="24" rx="3" fill="#0f172a"/>
              <rect x="14" y="70" width="16" height="16" rx="2" fill="white"/>
              <rect x="18" y="74" width="8" height="8" rx="1" fill="#0f172a"/>

              <!-- Random Data Dots -->
              <rect x="42" y="14" width="6" height="6" fill="#0f172a"/>
              <rect x="52" y="14" width="6" height="6" fill="#0f172a"/>
              <rect x="42" y="24" width="6" height="6" fill="#0f172a"/>
              <rect x="42" y="42" width="16" height="16" rx="2" fill="#10b981"/>
              <rect x="14" y="44" width="6" height="6" fill="#0f172a"/>
              <rect x="24" y="44" width="6" height="6" fill="#0f172a"/>
              <rect x="66" y="44" width="6" height="6" fill="#0f172a"/>
              <rect x="76" y="44" width="6" height="6" fill="#0f172a"/>
              <rect x="42" y="66" width="6" height="6" fill="#0f172a"/>
              <rect x="52" y="66" width="6" height="6" fill="#0f172a"/>
              <rect x="66" y="66" width="6" height="6" fill="#0f172a"/>
              <rect x="76" y="76" width="6" height="6" fill="#0f172a"/>
            </svg>
            <p class="text-[11px] text-slate-800 font-bold mt-1">امسح بكاميرا الهاتف للتحميل</p>
          </div>

          <!-- Direct Download CTA -->
          <div class="space-y-3 text-right">
            <a 
              href="/downloads/medical-crm-latest.apk" 
              download
              class="px-6 py-3.5 rounded-xl bg-gradient-to-r from-emerald-500 to-teal-500 hover:from-emerald-600 hover:to-teal-600 text-white font-bold text-sm shadow-xl shadow-emerald-500/25 flex items-center justify-center gap-2 cursor-pointer transition">
              <span>⬇️</span> تحميل ملف الـ APK المباشر
            </a>
            <p class="text-xs text-slate-400 leading-relaxed max-w-xs">
              لا يتطلب متجر Google Play. يمكن تثبيته وتفعيله مباشرة من الهاتف، ويستقبل التحديثات تلقائياً من داخل التطبيق.
            </p>
          </div>
        </div>

        <!-- Instructions Box -->
        <div class="p-4 rounded-xl bg-slate-800/40 text-xs text-slate-400 text-right space-y-1.5 border border-slate-800">
          <div class="font-bold text-slate-300">تعليمات التثبيت للمندوب:</div>
          <div>1. قم بتحميل الملف عبر مسح الـ QR أو الضغط على زر التحميل.</div>
          <div>2. عند اكتمال التحميل اضغط على الملف واختر "تثبيت" (إذا ظهر تحذير المصادر غير المعروفة اضغط السماح لهذا المصدر).</div>
          <div>3. افتح التطبيق وسجل الدخول بحساب المندوب الخاص بك لتبدأ العمل مباشرة.</div>
        </div>
      </div>
    {/if}

  </main>
</div>
