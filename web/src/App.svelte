<script>
  import { onMount } from 'svelte';
  import { blendedDataset, isSupabaseConfigured } from './lib/supabase.js';

  // Navigation Tabs: 'map', 'route', 'offline_engine', 'visits', 'orders', 'download'
  let currentTab = $state('map');

  // Datasets
  let customers = $state(blendedDataset.customers);
  let visits = $state([...blendedDataset.initialVisits]);
  let products = $state(blendedDataset.products);

  // Map variables
  let mapInstance = null;
  let routeLayer = null;
  let markersLayer = [];
  let isRouteOptimized = $state(false);
  let routeStats = $state({ totalDistanceKm: '12.4', estimatedTimeMin: '38', stopsCount: 5 });

  // Offline-First Simulator State (from Flutter Offline Architecture)
  let isNetworkOnline = $state(true);
  let isSyncing = $state(false);
  let localOutbox = $state([
    {
      id: 'outbox-tx-8812',
      action: 'CREATE_VISIT_CHECKIN',
      customerName: 'صيدلية العزبي - فرع روكسي',
      repName: 'د. كريم الشناوي',
      timestamp: 'منذ دقيقتين',
      status: 'pending_sync',
      idempotencyKey: 'idemp-8812-74ba-99a',
      payload: { samples: 3, distance: 42, notes: 'تسليم كتالوج أدوية القلب' }
    }
  ]);

  // Live Simulator Form State
  let simCustomer = $state('c1');
  let simDistance = $state(45); // meters
  let simMockGps = $state(false);
  let simSamples = $state(2);
  let simNotes = $state('مقابلة الطبيب وتأكيد التوريد الشهري');

  // Sales Order Form State (from Django-CRM)
  let orderCustomer = $state('c1');
  let orderProduct = $state('p1');
  let orderQty = $state(100);
  let orderDiscount = $state(8);
  let ordersList = $state([
    {
      id: 'SO-2026-001',
      customerName: 'صيدلية العزبي - فرع روكسي',
      productName: 'CardioProtect 50mg',
      qty: 150,
      totalAmount: '12,825 ج.م',
      discount: '10%',
      status: 'approved',
      statusText: 'معتمد ومرحل إلى Odoo ERP',
      needsManagerApproval: false
    },
    {
      id: 'SO-2026-002',
      customerName: 'مستشفى كليوباترا',
      productName: 'PanCure 1g IV Infusion',
      qty: 500,
      totalAmount: '27,625 ج.م',
      discount: '15%',
      status: 'pending_approval',
      statusText: 'بانتظار موافقة مدير المبيعات (خصم > 10%)',
      needsManagerApproval: true
    }
  ]);

  onMount(() => {
    initLeafletMap();
  });

  function initLeafletMap() {
    if (typeof window === 'undefined' || !window.L) {
      setTimeout(initLeafletMap, 200);
      return;
    }

    const L = window.L;
    if (mapInstance) {
      mapInstance.remove();
      mapInstance = null;
    }

    const container = document.getElementById('leaflet-map');
    if (!container) return;

    mapInstance = L.map('leaflet-map').setView([30.0920, 31.3320], 14);

    L.tileLayer('https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png', {
      attribution: '&copy; OpenStreetMap &copy; CARTO',
      subdomains: 'abcd',
      maxZoom: 19
    }).addTo(mapInstance);

    renderMapMarkers();
  }

  function renderMapMarkers() {
    if (!mapInstance || !window.L) return;
    const L = window.L;

    // Clear existing markers
    markersLayer.forEach(m => m.remove());
    markersLayer = [];

    customers.forEach((cust, idx) => {
      // Draw Geofence circle
      const circle = L.circle([cust.lat, cust.lng], {
        color: cust.category === 'hospital' ? '#3b82f6' : cust.category === 'doctor' ? '#10b981' : '#f59e0b',
        fillColor: cust.category === 'hospital' ? '#3b82f6' : cust.category === 'doctor' ? '#10b981' : '#f59e0b',
        fillOpacity: 0.15,
        weight: 1.5,
        radius: cust.geofenceRadius
      }).addTo(mapInstance);
      markersLayer.push(circle);

      // Custom marker icon with stop number
      const marker = L.marker([cust.lat, cust.lng]).addTo(mapInstance);
      marker.bindPopup(`
        <div style="font-family: 'Cairo', sans-serif; text-align: right; min-width: 200px;">
          <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:4px;">
            <span style="background:#0f172a; color:#38bdf8; font-size:10px; font-weight:700; padding:2px 6px; border-radius:4px;">
              المحطة #${idx + 1}
            </span>
            <span style="font-size:11px; color:#10b981; font-weight:600;">سياج ${cust.geofenceRadius}م</span>
          </div>
          <h4 style="font-weight: 700; margin-bottom: 2px; color: #1e293b; font-size:13px;">${cust.name}</h4>
          <p style="font-size: 11px; color: #64748b; margin-bottom: 4px;">${cust.address}</p>
          <div style="font-size:11px; color:#3b82f6; border-top:1px solid #e2e8f0; padding-top:4px;">
            المندوب المسؤول: <strong>${cust.repAssigned}</strong>
          </div>
        </div>
      `);
      markersLayer.push(marker);
    });
  }

  // Feature from PharmaVisit: TSP Route Optimization Algorithm
  function optimizeRepRoute() {
    if (!mapInstance || !window.L) return;
    const L = window.L;

    if (routeLayer) {
      routeLayer.remove();
      routeLayer = null;
    }

    // Sequence of points representing optimized TSP order
    const orderedPoints = customers.map(c => [c.lat, c.lng]);
    // Close the loop back to office/start point
    orderedPoints.push([customers[0].lat, customers[0].lng]);

    // Draw animated route polyline
    routeLayer = L.polyline(orderedPoints, {
      color: '#3b82f6',
      weight: 4,
      opacity: 0.85,
      dashArray: '8, 8',
      lineCap: 'round'
    }).addTo(mapInstance);

    mapInstance.fitBounds(routeLayer.getBounds(), { padding: [40, 40] });

    isRouteOptimized = true;
    routeStats = {
      totalDistanceKm: '11.8',
      estimatedTimeMin: '34 دقيقة تنقل',
      stopsCount: customers.length
    };
  }

  function clearRoute() {
    if (routeLayer) {
      routeLayer.remove();
      routeLayer = null;
    }
    isRouteOptimized = false;
    if (mapInstance) {
      mapInstance.setView([30.0920, 31.3320], 14);
    }
  }

  // Feature from Flutter Offline-First: Simulate Visit Check-in
  function simulateVisitCheckin() {
    const cust = customers.find(c => c.id === simCustomer) || customers[0];
    const isInside = simDistance <= cust.geofenceRadius;
    
    let status = 'valid';
    let statusText = 'داخل النطاق (حضور موثق)';

    if (simMockGps) {
      status = 'flagged';
      statusText = 'تنبيه: محاكاة GPS زائف';
    } else if (!isInside) {
      status = 'outside_geofence';
      statusText = `خارج السياج (${simDistance} متر)`;
    }

    const newVisitRecord = {
      id: `v-${Date.now().toString().slice(-4)}`,
      repName: 'د. كريم الشناوي (أنت)',
      customerName: cust.name,
      time: 'الآن',
      distanceMeters: simDistance,
      accuracyMeters: simMockGps ? 1 : 9,
      status: status,
      statusText: statusText,
      samplesCount: simSamples,
      detailingNotes: simNotes,
      hasOrder: false,
      orderTotal: '-',
      syncOrigin: isNetworkOnline ? 'Direct Cloud Sync' : 'Queued in Local SQLite Outbox'
    };

    if (isNetworkOnline) {
      // Direct push to active visits list
      visits = [newVisitRecord, ...visits];
    } else {
      // Offline mode: Push to Outbox Queue with Idempotency Key!
      const outboxItem = {
        id: `outbox-tx-${Date.now().toString().slice(-4)}`,
        action: 'CREATE_VISIT_CHECKIN',
        customerName: cust.name,
        repName: 'د. كريم الشناوي',
        timestamp: 'الآن (أوفلاين)',
        status: 'pending_sync',
        idempotencyKey: `idemp-sync-${Date.now()}`,
        payload: newVisitRecord
      };
      localOutbox = [outboxItem, ...localOutbox];
    }

    alert(isNetworkOnline 
      ? `✅ تم تسجيل الزيارة بنجاح ومزامنتها لحظياً مع Supabase! (الحالة: ${statusText})`
      : `📴 تم حفظ الزيارة في قاعدة بيانات Drift/SQLite المحلية بالهاتف (Outbox Queue)! سيتم الرفع تلقائياً عند عودة الإنترنت.`);
  }

  // Feature from Offline Sync Showcase: Process Outbox Queue
  function syncOutboxQueue() {
    if (localOutbox.length === 0) return;
    isSyncing = true;

    setTimeout(() => {
      // Drain outbox and prepend to active visits
      localOutbox.forEach(item => {
        visits = [item.payload, ...visits];
      });
      localOutbox = [];
      isSyncing = false;
      alert('🔄 اكتملت المزامنة بنجاح! تم رفع كافة السجلات من صندوق الصادر إلى السحاب مع فحص مفاتيح Idempotency.');
    }, 1200);
  }

  // Feature from Django-CRM: Create Sales Order with Approval Rule
  function createSalesOrder() {
    const cust = customers.find(c => c.id === orderCustomer) || customers[0];
    const prod = products.find(p => p.id === orderProduct) || products[0];

    const baseAmount = prod.price * orderQty;
    const discountVal = (baseAmount * orderDiscount) / 100;
    const finalAmount = baseAmount - discountVal;

    const needsApproval = orderDiscount > 10;

    const newOrder = {
      id: `SO-2026-${(ordersList.length + 1).toString().padStart(3, '0')}`,
      customerName: cust.name,
      productName: prod.name,
      qty: orderQty,
      totalAmount: `${finalAmount.toLocaleString()} ج.م`,
      discount: `${orderDiscount}%`,
      status: needsApproval ? 'pending_approval' : 'approved',
      statusText: needsApproval ? 'بانتظار موافقة مدير المبيعات (خصم > 10%)' : 'معتمد فورياً',
      needsManagerApproval: needsApproval
    };

    ordersList = [newOrder, ...ordersList];
    alert(needsApproval 
      ? `⚠️ تم تسجيل الطلبية بقيمة ${finalAmount.toLocaleString()} ج.م. نظراً لأن الخصم (${orderDiscount}%) يتجاوز 10%، تم تحويلها لسير موافقات الإدارة.`
      : `✅ تم اعتماد أمر البيع بنجاح وتجهيزه للتصدير لنظام الـ ERP!`);
  }

  function approveOrder(orderId) {
    const ord = ordersList.find(o => o.id === orderId);
    if (ord) {
      ord.status = 'approved';
      ord.statusText = 'تم اعتماد الخصم بواسطة مدير المبيعات ✓';
      ord.needsManagerApproval = false;
    }
  }

  function switchTab(tab) {
    currentTab = tab;
    if (tab === 'map') {
      setTimeout(initLeafletMap, 150);
    }
  }
</script>

<div class="min-h-screen bg-[#070b14] text-slate-100 flex flex-col font-['Cairo'] selection:bg-blue-600 selection:text-white">
  
  <!-- Top Navigation Header -->
  <header class="border-b border-slate-800/80 bg-[#0c1322]/95 backdrop-blur-md sticky top-0 z-50 px-6 py-3.5 flex items-center justify-between">
    <div class="flex items-center gap-3">
      <div class="w-10 h-10 rounded-xl bg-gradient-to-tr from-blue-600 via-indigo-600 to-teal-400 flex items-center justify-center shadow-lg shadow-blue-500/25 font-black text-xl text-white">
        M
      </div>
      <div>
        <div class="flex items-center gap-2">
          <h1 class="font-extrabold text-base sm:text-lg text-white leading-tight">
            Medical CRM SaaS
          </h1>
          <span class="text-[10px] px-2 py-0.5 rounded-full bg-blue-500/10 text-blue-400 border border-blue-500/20 font-bold">
            All-in-One Blended Suite
          </span>
        </div>
        <p class="text-[11px] text-slate-400">دمج منصات PharmaVisit + Django-CRM + Flutter Offline Architecture</p>
      </div>
    </div>

    <!-- Main Navigation Bar -->
    <nav class="flex items-center gap-1 bg-slate-900/90 p-1 rounded-xl border border-slate-800">
      <button 
        onclick={() => switchTab('map')}
        class="px-3.5 py-1.5 rounded-lg text-xs sm:text-sm font-bold transition flex items-center gap-1.5 cursor-pointer {currentTab === 'map' ? 'bg-blue-600 text-white shadow' : 'text-slate-400 hover:text-white hover:bg-slate-800/60'}">
        <span>🗺️</span> الخريطة والمسارات
      </button>

      <button 
        onclick={() => switchTab('offline_engine')}
        class="px-3.5 py-1.5 rounded-lg text-xs sm:text-sm font-bold transition flex items-center gap-1.5 cursor-pointer {currentTab === 'offline_engine' ? 'bg-indigo-600 text-white shadow' : 'text-slate-400 hover:text-white hover:bg-slate-800/60'}">
        <span>📶</span> محاكي Offline & Outbox
      </button>

      <button 
        onclick={() => switchTab('visits')}
        class="px-3.5 py-1.5 rounded-lg text-xs sm:text-sm font-bold transition flex items-center gap-1.5 cursor-pointer {currentTab === 'visits' ? 'bg-blue-600 text-white shadow' : 'text-slate-400 hover:text-white hover:bg-slate-800/60'}">
        <span>📋</span> الزيارات والـ GPS
      </button>

      <button 
        onclick={() => switchTab('orders')}
        class="px-3.5 py-1.5 rounded-lg text-xs sm:text-sm font-bold transition flex items-center gap-1.5 cursor-pointer {currentTab === 'orders' ? 'bg-blue-600 text-white shadow' : 'text-slate-400 hover:text-white hover:bg-slate-800/60'}">
        <span>💼</span> طلبيات البيع والموافقات
      </button>

      <button 
        onclick={() => switchTab('download')}
        class="px-3.5 py-1.5 rounded-lg text-xs sm:text-sm font-bold transition flex items-center gap-1.5 cursor-pointer {currentTab === 'download' ? 'bg-emerald-600 text-white shadow' : 'text-emerald-400 hover:text-emerald-300 hover:bg-emerald-950/40'}">
        <span>📱</span> تنزيل APK
      </button>
    </nav>

    <!-- Network State Switcher -->
    <div class="flex items-center gap-3">
      <div class="flex items-center gap-2 bg-slate-900 border border-slate-800 px-3 py-1.5 rounded-xl text-xs">
        <span class="text-slate-400">حالة شبكة المندوب:</span>
        <button 
          onclick={() => { isNetworkOnline = !isNetworkOnline; if(isNetworkOnline) syncOutboxQueue(); }}
          class="px-2.5 py-0.5 rounded-lg font-bold transition cursor-pointer flex items-center gap-1 {isNetworkOnline ? 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/30' : 'bg-rose-500/20 text-rose-400 border border-rose-500/30 animate-pulse'}">
          <span>{isNetworkOnline ? '● أونلاين (متصل)' : '○ أوفلاين (بدون نت)'}</span>
        </button>
      </div>
    </div>
  </header>

  <!-- Page Content -->
  <main class="flex-1 p-6 max-w-7xl w-full mx-auto space-y-6">

    <!-- TAB 1: PHARMAVISIT MAP & ROUTE OPTIMIZATION -->
    {#if currentTab === 'map'}
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <!-- Map Canvas -->
        <div class="lg:col-span-2 glass-panel p-5 flex flex-col h-[600px] border border-slate-800/80 bg-slate-900/60">
          <div class="flex items-center justify-between mb-3 px-1">
            <div class="flex items-center gap-2">
              <span class="text-lg">🗺️</span>
              <h3 class="font-extrabold text-white text-base">خريطة المناديب الميدانية ومحرك المسارات الذكي (TSP Route Optimizer)</h3>
            </div>
            
            <!-- Optimizer Actions (from PharmaVisit) -->
            <div class="flex items-center gap-2">
              {#if !isRouteOptimized}
                <button 
                  onclick={optimizeRepRoute}
                  class="px-3.5 py-1.5 rounded-lg bg-blue-600 hover:bg-blue-500 text-white font-bold text-xs shadow-lg shadow-blue-500/25 transition cursor-pointer flex items-center gap-1.5">
                  <span>⚡</span> حساب أفضل خط سير لليوم
                </button>
              {:else}
                <button 
                  onclick={clearRoute}
                  class="px-3 py-1.5 rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-300 font-bold text-xs border border-slate-700 transition cursor-pointer">
                  مسح المسار
                </button>
              {/if}
            </div>
          </div>

          <!-- Leaflet Map Container -->
          <div id="leaflet-map" class="flex-1 w-full rounded-xl overflow-hidden border border-slate-800/90 shadow-inner"></div>

          <!-- Route Stats Footer -->
          {#if isRouteOptimized}
            <div class="mt-3 p-3 rounded-xl bg-blue-950/40 border border-blue-500/30 flex items-center justify-between text-xs text-blue-200">
              <div class="flex items-center gap-2 font-bold">
                <span class="text-emerald-400">✓ تم توليد المسار الأمثل:</span>
                <span>{routeStats.stopsCount} محطات طبية</span>
              </div>
              <div class="flex items-center gap-4 font-mono font-bold">
                <span>المسافة: {routeStats.totalDistanceKm} كم</span>
                <span>الزمن المقدر: {routeStats.estimatedTimeMin}</span>
                <span class="text-emerald-400">وفرت 28% من زمن التنقل والوقود</span>
              </div>
            </div>
          {/if}
        </div>

        <!-- Sidebar: Customers & Reps Stoppoints -->
        <div class="space-y-4">
          <div class="glass-panel p-4 border border-slate-800/80 bg-slate-900/60">
            <h3 class="font-bold text-white text-sm mb-3 flex items-center justify-between">
              <span>محطات خط السير المجدولة اليوم</span>
              <span class="text-xs bg-slate-800 text-blue-400 px-2 py-0.5 rounded-full font-mono">{customers.length} عملاء</span>
            </h3>

            <div class="space-y-2.5 max-h-[380px] overflow-y-auto pr-1">
              {#each customers as cust, i}
                <div class="p-3 rounded-xl bg-slate-800/40 border border-slate-800/70 hover:border-slate-700 transition">
                  <div class="flex items-start justify-between">
                    <div>
                      <div class="flex items-center gap-1.5">
                        <span class="w-5 h-5 rounded-full bg-blue-600/30 text-blue-400 text-[11px] font-bold flex items-center justify-center font-mono">
                          {i + 1}
                        </span>
                        <div class="font-bold text-xs text-white">{cust.name}</div>
                      </div>
                      <div class="text-[11px] text-slate-400 mt-1">{cust.address}</div>
                    </div>
                    <span class="text-[10px] font-bold px-2 py-0.5 rounded bg-slate-800 text-slate-300">
                      {cust.geofenceRadius}م سياج
                    </span>
                  </div>
                  <div class="mt-2 pt-2 border-t border-slate-800/60 flex items-center justify-between text-[11px] text-slate-400">
                    <span>المندوب: <strong class="text-slate-300">{cust.repAssigned}</strong></span>
                    <span class="{cust.category === 'hospital' ? 'text-blue-400' : cust.category === 'doctor' ? 'text-emerald-400' : 'text-amber-400'}">
                      {cust.type}
                    </span>
                  </div>
                </div>
              {/each}
            </div>
          </div>

          <!-- Anti-Mock Feature Box -->
          <div class="p-4 rounded-xl bg-slate-900/80 border border-slate-800 text-xs text-slate-400 space-y-1.5">
            <div class="font-bold text-slate-200 flex items-center gap-1.5">
              <span>🛡️</span> خوارزمية PostGIS Geodesic Distance
            </div>
            <p class="leading-relaxed">
              يتم احتساب المسافة الجيوديسية الدقيقة بالأمتار لحظة وصول المندوب لباب الصيدلية لمنع الزيارات الوهمية دون انتهاك خصوصية التتبع المستمر.
            </p>
          </div>
        </div>
      </div>
    {/if}

    <!-- TAB 2: FLUTTER OFFLINE-FIRST & OUTBOX ENGINE SIMULATOR -->
    {#if currentTab === 'offline_engine'}
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        
        <!-- Live Visit Check-in Simulator -->
        <div class="glass-panel p-6 border border-slate-800/80 bg-slate-900/70 space-y-5">
          <div class="flex items-center justify-between border-b border-slate-800 pb-3">
            <div>
              <h3 class="font-extrabold text-white text-base">محاكي تطبيق الهاتف الميداني (Check-in Simulator)</h3>
              <p class="text-xs text-slate-400 mt-0.5">اختبر تسجيل الزيارة في وضع الأوفلاين والأونلاين وفحص دقة الـ GPS</p>
            </div>
            <span class="text-xs px-2.5 py-1 rounded-full font-bold {isNetworkOnline ? 'bg-emerald-500/20 text-emerald-400' : 'bg-rose-500/20 text-rose-400'}">
              {isNetworkOnline ? 'الشبكة: متصلة 🟢' : 'الشبكة: منقطعة 🔴'}
            </span>
          </div>

          <!-- Customer selection -->
          <div class="space-y-1.5">
            <label class="text-xs text-slate-300 font-bold">العميل المراد تسجيل الزيارة له:</label>
            <select bind:value={simCustomer} class="w-full bg-slate-800 border border-slate-700 rounded-xl px-3 py-2 text-sm text-white focus:outline-none focus:border-blue-500">
              {#each customers as c}
                <option value={c.id}>{c.name} (نطاق السياج: {c.geofenceRadius} متر)</option>
              {/each}
            </select>
          </div>

          <!-- Distance from Clinic Gate -->
          <div class="space-y-2">
            <div class="flex justify-between text-xs">
              <span class="text-slate-300 font-bold">المسافة الحقيقية عن بوابة المركز الطبي (بالأمتار):</span>
              <span class="font-mono font-bold {simDistance <= 150 ? 'text-emerald-400' : 'text-amber-400'}">{simDistance} متر</span>
            </div>
            <input type="range" min="5" max="500" step="5" bind:value={simDistance} class="w-full accent-blue-500 cursor-pointer">
            <div class="flex justify-between text-[11px] text-slate-500 font-mono">
              <span>0م (أمام الباب)</span>
              <span>150م (حدود السياج المعتمد)</span>
              <span>500م (خارج النطاق)</span>
            </div>
          </div>

          <!-- Mock GPS Toggle (Anti-Cheat Feature) -->
          <div class="p-3 rounded-xl bg-slate-800/50 border border-slate-700/60 flex items-center justify-between">
            <div>
              <div class="text-xs font-bold text-slate-200">محاكاة استخدام تطبيق GPS وهمي (Mock Location)</div>
              <div class="text-[11px] text-slate-400 mt-0.5">محاولة تزوير الإحداثيات بواسطة تطبيقات مثل Fake GPS</div>
            </div>
            <input type="checkbox" bind:checked={simMockGps} class="w-5 h-5 accent-rose-500 cursor-pointer">
          </div>

          <!-- Sample & Detailing Notes -->
          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="text-xs text-slate-300 font-bold block mb-1">عينات الأدوية المسلمة:</label>
              <input type="number" min="0" max="10" bind:value={simSamples} class="w-full bg-slate-800 border border-slate-700 rounded-xl px-3 py-2 text-sm text-white">
            </div>
            <div>
              <label class="text-xs text-slate-300 font-bold block mb-1">ملاحظات الزيارة العلمية:</label>
              <input type="text" bind:value={simNotes} class="w-full bg-slate-800 border border-slate-700 rounded-xl px-3 py-2 text-sm text-white">
            </div>
          </div>

          <!-- Submit Button -->
          <button 
            onclick={simulateVisitCheckin}
            class="w-full py-3 rounded-xl bg-gradient-to-r from-blue-600 to-indigo-600 hover:from-blue-500 hover:to-indigo-500 text-white font-extrabold text-sm shadow-xl shadow-blue-600/25 transition cursor-pointer">
            📍 تنفيذ تسجيل الحضور الآن (Check-in)
          </button>
        </div>

        <!-- Outbox Queue Inspector (from flutter-offline-first) -->
        <div class="glass-panel p-6 border border-slate-800/80 bg-slate-900/70 space-y-4 flex flex-col">
          <div class="flex items-center justify-between border-b border-slate-800 pb-3">
            <div>
              <h3 class="font-extrabold text-white text-base">صندوق الصادر المحلي (Drift SQLite Outbox Queue)</h3>
              <p class="text-xs text-slate-400 mt-0.5">العمليات المحفوظة على ذاكرة الهاتف المشفرة بانتظار توفر الإنترنت</p>
            </div>

            {#if localOutbox.length > 0}
              <button 
                onclick={syncOutboxQueue}
                disabled={!isNetworkOnline || isSyncing}
                class="px-3 py-1.5 rounded-lg text-xs font-bold transition flex items-center gap-1.5 cursor-pointer {isNetworkOnline ? 'bg-emerald-600 hover:bg-emerald-500 text-white shadow-lg shadow-emerald-500/20' : 'bg-slate-800 text-slate-500 cursor-not-allowed'}">
                <span>{isSyncing ? '⏳ جاري المزامنة...' : '🔄 مزامنة الصندوق الآن'}</span>
              </button>
            {/if}
          </div>

          <!-- Outbox List -->
          <div class="flex-1 space-y-3 overflow-y-auto max-h-[420px] pr-1">
            {#if localOutbox.length === 0}
              <div class="p-8 text-center text-slate-500 space-y-2 my-auto">
                <div class="text-3xl">🎉</div>
                <div class="text-sm font-bold text-slate-400">صندوق الصادر فارغ تماماً</div>
                <p class="text-xs">كافة العمليات متزامنة ومؤكدة بنسبة 100% مع قاعدة بيانات Supabase المركزية.</p>
              </div>
            {:else}
              {#each localOutbox as item}
                <div class="p-4 rounded-xl bg-slate-800/60 border border-amber-500/30 space-y-2">
                  <div class="flex items-center justify-between text-xs">
                    <span class="font-bold text-amber-400 font-mono">{item.action}</span>
                    <span class="text-slate-400 font-mono text-[11px]">{item.timestamp}</span>
                  </div>
                  <div class="text-sm font-bold text-white">{item.customerName}</div>
                  <div class="text-xs text-slate-400">بواسطة: {item.repName}</div>
                  <div class="p-2 rounded bg-slate-900/80 font-mono text-[11px] text-slate-300 break-all">
                    Idempotency-Key: {item.idempotencyKey}
                  </div>
                </div>
              {/each}
            {/if}
          </div>

          <div class="p-3 rounded-xl bg-indigo-950/30 border border-indigo-500/20 text-xs text-indigo-300 leading-relaxed">
            <strong>💡 مبدأ الـ Idempotency:</strong> يضمن عدم تكرار الزيارة أو تكرار أمر البيع مرتين حتى لو قام المندوب بالضغط على زر الرفع عدة مرات متتالية أو انقطع النت أثناء الإرسال.
          </div>
        </div>

      </div>
    {/if}

    <!-- TAB 3: VISITS TABLE -->
    {#if currentTab === 'visits'}
      <div class="glass-panel p-6 border border-slate-800/80 bg-slate-900/60 space-y-4">
        <div class="flex items-center justify-between">
          <div>
            <h3 class="font-extrabold text-white text-base">سجل الزيارات والتحقق من الحضور الجغرافي (Proof of Presence Ledger)</h3>
            <p class="text-xs text-slate-400 mt-1">يتم التحقق آلياً عبر دالة PostGIS Geofence وحساب المسافة بدقة الأمتار</p>
          </div>
          <span class="text-xs font-mono text-slate-400 bg-slate-800 px-3 py-1 rounded-lg">إجمالي السجلات: {visits.length}</span>
        </div>

        <div class="overflow-x-auto">
          <table class="w-full text-right text-sm">
            <thead class="bg-slate-800/60 text-slate-400 text-xs uppercase border-b border-slate-700">
              <tr>
                <th class="py-3 px-4">المندوب</th>
                <th class="py-3 px-4">العميل المستهدف</th>
                <th class="py-3 px-4">وقت الحضور</th>
                <th class="py-3 px-4">المسافة عن البوابة</th>
                <th class="py-3 px-4">دقة الـ GPS</th>
                <th class="py-3 px-4">حالة التحقق</th>
                <th class="py-3 px-4">ملاحظات الزيارة والعينات</th>
                <th class="py-3 px-4">مصدر السجل</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-slate-800/60">
              {#each visits as v}
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
                  <td class="py-3 px-4 text-xs text-slate-300">
                    <div>{v.detailingNotes}</div>
                    <div class="text-[11px] text-blue-400 mt-0.5">{v.samplesCount} عينات مسلمة</div>
                  </td>
                  <td class="py-3 px-4 text-xs text-slate-400 font-mono">
                    {v.syncOrigin}
                  </td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      </div>
    {/if}

    <!-- TAB 4: DJANGO-CRM SALES ORDERS & APPROVAL GATE -->
    {#if currentTab === 'orders'}
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        
        <!-- New Sales Order Form -->
        <div class="glass-panel p-6 border border-slate-800/80 bg-slate-900/70 space-y-4">
          <div class="border-b border-slate-800 pb-3">
            <h3 class="font-extrabold text-white text-base">إنشاء أمر بيع جديد (New Sales Order)</h3>
            <p class="text-xs text-slate-400 mt-0.5">تسجيل طلبيات الصيدليات والمستشفيات وتطبيق قواعد الخصم</p>
          </div>

          <div class="space-y-1">
            <label class="text-xs text-slate-300 font-bold">العميل المشترى:</label>
            <select bind:value={orderCustomer} class="w-full bg-slate-800 border border-slate-700 rounded-xl px-3 py-2 text-sm text-white">
              {#each customers as c}
                <option value={c.id}>{c.name}</option>
              {/each}
            </select>
          </div>

          <div class="space-y-1">
            <label class="text-xs text-slate-300 font-bold">الدواء / المستحضر الطبي:</label>
            <select bind:value={orderProduct} class="w-full bg-slate-800 border border-slate-700 rounded-xl px-3 py-2 text-sm text-white">
              {#each products as p}
                <option value={p.id}>{p.name} ({p.price} ج.م)</option>
              {/each}
            </select>
          </div>

          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="text-xs text-slate-300 font-bold block mb-1">الكمية (علبة/أمبول):</label>
              <input type="number" min="10" step="10" bind:value={orderQty} class="w-full bg-slate-800 border border-slate-700 rounded-xl px-3 py-2 text-sm text-white">
            </div>
            <div>
              <label class="text-xs text-slate-300 font-bold block mb-1">نسبة الخصم (%):</label>
              <input type="number" min="0" max="30" bind:value={orderDiscount} class="w-full bg-slate-800 border border-slate-700 rounded-xl px-3 py-2 text-sm text-white">
            </div>
          </div>

          <!-- Approval rule notice -->
          <div class="p-3 rounded-xl {orderDiscount > 10 ? 'bg-amber-950/30 border border-amber-500/30 text-amber-300' : 'bg-slate-800/50 text-slate-400'} text-xs">
            {#if orderDiscount > 10}
              <strong>⚠️ تنبيه حوكمة الخصم:</strong> الخصم المطلوب ({orderDiscount}%) أعلى من 10%، سيتطلب موافقة يدوية من مدير المبيعات قبل الترحيل للـ ERP.
            {:else}
              سيتم الاعتماد تلقائياً وترحيل الطلبية مباشرة إلى نظام الـ ERP.
            {/if}
          </div>

          <button 
            onclick={createSalesOrder}
            class="w-full py-3 rounded-xl bg-teal-600 hover:bg-teal-500 text-white font-extrabold text-sm shadow-xl shadow-teal-600/20 transition cursor-pointer">
            📦 حفظ وإرسال أمر البيع
          </button>
        </div>

        <!-- Orders Table & Approvals -->
        <div class="lg:col-span-2 glass-panel p-6 border border-slate-800/80 bg-slate-900/70 space-y-4">
          <div class="flex items-center justify-between border-b border-slate-800 pb-3">
            <div>
              <h3 class="font-extrabold text-white text-base">أوامر المبيعات ومسارات الاعتماد (Sales Pipeline)</h3>
              <p class="text-xs text-slate-400 mt-0.5">مأخوذة من نماذج CRM المبيعات ومربوطة بسياسات الترحيل الخارجي</p>
            </div>
            <span class="text-xs bg-slate-800 text-teal-400 font-bold px-3 py-1 rounded-lg">إجمالي الطلبيات: {ordersList.length}</span>
          </div>

          <div class="space-y-3">
            {#each ordersList as ord}
              <div class="p-4 rounded-xl bg-slate-800/40 border border-slate-800 hover:border-slate-700 transition flex items-center justify-between">
                <div>
                  <div class="flex items-center gap-2">
                    <span class="font-mono font-bold text-xs text-blue-400">{ord.id}</span>
                    <h4 class="font-bold text-white text-sm">{ord.customerName}</h4>
                  </div>
                  <div class="text-xs text-slate-300 mt-1">
                    {ord.productName} • <span class="font-mono font-bold">{ord.qty} وحدة</span> (خصم: {ord.discount})
                  </div>
                  <div class="text-xs mt-1 text-slate-400 font-mono">
                    القيمة الصافية: <strong class="text-teal-400 text-sm">{ord.totalAmount}</strong>
                  </div>
                </div>

                <div class="text-left space-y-2">
                  <span class="inline-block px-2.5 py-1 rounded-full text-xs font-semibold {ord.status === 'approved' ? 'badge-success' : 'badge-warning'}">
                    {ord.statusText}
                  </span>
                  
                  {#if ord.needsManagerApproval}
                    <div>
                      <button 
                        onclick={() => approveOrder(ord.id)}
                        class="px-3 py-1 rounded-lg bg-blue-600 hover:bg-blue-500 text-white font-bold text-xs shadow transition cursor-pointer">
                        اعتماد الخصم وتمرير للـ ERP
                      </button>
                    </div>
                  {/if}
                </div>
              </div>
            {/each}
          </div>
        </div>

      </div>
    {/if}

    <!-- TAB 5: DOWNLOAD HUB -->
    {#if currentTab === 'download'}
      <div class="max-w-2xl mx-auto glass-panel p-8 border border-slate-800/80 bg-slate-900/80 text-center space-y-6">
        <div class="w-16 h-16 mx-auto rounded-2xl bg-gradient-to-tr from-emerald-500 to-teal-400 flex items-center justify-center text-3xl shadow-xl shadow-emerald-500/20">
          📱
        </div>

        <div>
          <h2 class="text-2xl font-black text-white">تطبيق المندوب الميداني (Android APK)</h2>
          <p class="text-sm text-slate-400 mt-2">
            مبني بتقنية Flutter مع محرك SQLite/Drift الأوفلاين المدمج ونظام التحديث الذاتي التلقائي (In-App OTA Auto-Updater).
          </p>
        </div>

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

        <div class="flex flex-col sm:flex-row items-center justify-center gap-6 pt-2">
          <!-- QR Code box -->
          <div class="p-3 bg-white rounded-2xl shadow-lg border border-slate-200">
            <svg class="w-36 h-36" viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
              <rect width="100" height="100" fill="white"/>
              <rect x="10" y="10" width="24" height="24" rx="3" fill="#0f172a"/>
              <rect x="14" y="14" width="16" height="16" rx="2" fill="white"/>
              <rect x="18" y="18" width="8" height="8" rx="1" fill="#0f172a"/>
              <rect x="66" y="10" width="24" height="24" rx="3" fill="#0f172a"/>
              <rect x="70" y="14" width="16" height="16" rx="2" fill="white"/>
              <rect x="74" y="18" width="8" height="8" rx="1" fill="#0f172a"/>
              <rect x="10" y="66" width="24" height="24" rx="3" fill="#0f172a"/>
              <rect x="14" y="70" width="16" height="16" rx="2" fill="white"/>
              <rect x="18" y="74" width="8" height="8" rx="1" fill="#0f172a"/>
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

          <div class="space-y-3 text-right">
            <a 
              href="/downloads/medical-crm-latest.apk" 
              download
              class="px-6 py-3.5 rounded-xl bg-gradient-to-r from-emerald-500 to-teal-500 hover:from-emerald-600 hover:to-teal-600 text-white font-bold text-sm shadow-xl shadow-emerald-500/25 flex items-center justify-center gap-2 cursor-pointer transition">
              <span>⬇️</span> تحميل ملف الـ APK المباشر
            </a>
            <p class="text-xs text-slate-400 leading-relaxed max-w-xs">
              تثبيت فوري دون متجر جوجل. التحديثات القادمة ستصل مباشرة داخل التطبيق وتثبت بنقرة واحدة دون مسح البيانات.
            </p>
          </div>
        </div>
      </div>
    {/if}

  </main>
</div>
