/**
 * Workmate4u Smart Category Picker
 * - Replaces native <select> with a searchable, grouped combobox.
 * - Keeps underlying <select> in sync so existing form/JS code still works.
 * - Auto-enhances #modalTaskCategory, #editTaskCategory, #filterCategory.
 */
(function () {
    'use strict';

    // --- Single source of truth for categories -----------------------------
    // Each entry: { key, label, parent, keywords:[] }
    const CATEGORIES = [
        // Home Repairs & Maintenance
        { key: 'plumbing',    label: 'Plumbing',              parent: 'Home Repairs',         icon: '🚰', keywords: ['tap','leak','pipe','toilet','drain','faucet','sink','geyser','flush','water'] },
        { key: 'electrician', label: 'Electrician',           parent: 'Home Repairs',         icon: '⚡', keywords: ['wiring','switch','fan','light','bulb','mcb','fuse','socket','short circuit','power'] },
        { key: 'carpentry',   label: 'Carpentry',             parent: 'Home Repairs',         icon: '🪚', keywords: ['wood','door','window','furniture','hinge','drawer','cabinet','shelf','assembly'] },
        { key: 'painting',    label: 'Painting & Decor',      parent: 'Home Repairs',         icon: '🎨', keywords: ['paint','wall','color','interior','exterior','primer','whitewash','distemper'] },
        { key: 'repair',      label: 'Repairs & Mechanical',  parent: 'Home Repairs',         icon: '🛠️', keywords: ['fix','broken','mechanical','machine','appliance','ac','fridge','washing machine'] },
        { key: 'vehicle',     label: 'Vehicle Services',      parent: 'Home Repairs',         icon: '🚗', keywords: ['car','bike','motorcycle','wash','service','puncture','tyre','battery','mechanic'] },

        // Cleaning & Household
        { key: 'household',   label: 'Household Chores',      parent: 'Cleaning & Household', icon: '🏠', keywords: ['chores','helper','dishes','utensils','dusting','sweeping','mopping','daily'] },
        { key: 'cleaning',    label: 'Cleaning Services',     parent: 'Cleaning & Household', icon: '🧽', keywords: ['clean','deep clean','sofa','carpet','bathroom','kitchen','vacuum'] },
        { key: 'laundry',     label: 'Laundry & Ironing',     parent: 'Cleaning & Household', icon: '👕', keywords: ['wash clothes','iron','dry clean','press','ironing','fold'] },
        { key: 'gardening',   label: 'Gardening & Lawn',      parent: 'Cleaning & Household', icon: '🌱', keywords: ['plant','garden','lawn','mowing','grass','tree','flower','soil'] },
        { key: 'waste',       label: 'Waste Collection',      parent: 'Cleaning & Household', icon: '🗑️', keywords: ['garbage','trash','dispose','scrap','recycle','dustbin','collection'] },
        { key: 'moving',      label: 'Moving & Packing',      parent: 'Cleaning & Household', icon: '📦', keywords: ['shift','relocate','packers','movers','boxes','furniture moving','loading'] },

        // Errands & Delivery
        { key: 'delivery',    label: 'Delivery Services',     parent: 'Errands & Delivery',   icon: '🛵', keywords: ['deliver','courier','pickup','drop','parcel','package','document'] },
        { key: 'transport',   label: 'Pick & Drop',           parent: 'Errands & Delivery',   icon: '🚕', keywords: ['drop','pick','ride','airport','station','school','transport'] },
        { key: 'shopping',    label: 'Shopping & Errands',    parent: 'Errands & Delivery',   icon: '🛒', keywords: ['buy','grocery','market','shop','store','errand','purchase'] },

        // Personal Care & Family
        { key: 'petcare',     label: 'Pet Care',              parent: 'Personal Care',        icon: '🐶', keywords: ['dog','cat','pet','walk','grooming','feed','vet','sitting'] },
        { key: 'beauty',      label: 'Beauty & Wellness',     parent: 'Personal Care',        icon: '💅', keywords: ['salon','haircut','makeup','spa','wax','manicure','pedicure','facial','threading'] },
        { key: 'babysitting', label: 'Babysitting',           parent: 'Personal Care',        icon: '🍼', keywords: ['baby','kid','child','nanny','sitter','daycare','toddler'] },
        { key: 'eldercare',   label: 'Elder Care',            parent: 'Personal Care',        icon: '🧓', keywords: ['elder','senior','old','grandma','grandpa','attendant','nursing'] },
        { key: 'fitness',     label: 'Fitness Training',      parent: 'Personal Care',        icon: '🏋️', keywords: ['gym','trainer','yoga','workout','exercise','zumba','aerobics','personal training'] },

        // Food & Events
        { key: 'cooking',     label: 'Cooking & Chef',        parent: 'Food & Events',        icon: '👨‍🍳', keywords: ['cook','chef','meal','food','tiffin','recipe','kitchen help'] },
        { key: 'catering',    label: 'Catering Services',     parent: 'Food & Events',        icon: '🍱', keywords: ['catering','party food','wedding food','event food','buffet'] },
        { key: 'eventhelp',   label: 'Event Help',            parent: 'Food & Events',        icon: '🎉', keywords: ['event','party','wedding','decoration','setup','volunteer','host'] },
        { key: 'photography', label: 'Photography',           parent: 'Food & Events',        icon: '📷', keywords: ['photo','photographer','shoot','video','wedding','portrait','camera'] },

        // Digital & Skilled Services
        { key: 'tutoring',    label: 'Online Tutoring',       parent: 'Digital & Skills',     icon: '📚', keywords: ['teach','tutor','study','class','math','science','english','coaching','homework'] },
        { key: 'techsupport', label: 'Tech Support',          parent: 'Digital & Skills',     icon: '💻', keywords: ['computer','laptop','wifi','internet','software','printer','mobile','phone fix'] },
        { key: 'freelance',   label: 'Freelance Services',    parent: 'Digital & Skills',     icon: '✍️', keywords: ['design','logo','website','content','writing','graphic','editing','marketing','seo'] },
        { key: 'tailoring',   label: 'Tailoring & Alterations', parent: 'Digital & Skills',   icon: '🧵', keywords: ['stitch','sew','alter','dress','blouse','cloth','tailor','fitting'] },

        // Other
        { key: 'other',       label: 'Other',                 parent: 'Other',                icon: '✨', keywords: ['miscellaneous','custom'] },
    ];

    const PARENT_ORDER = ['Home Repairs','Cleaning & Household','Errands & Delivery','Personal Care','Food & Events','Digital & Skills','Other'];
    const PARENT_ICONS = {
        'Home Repairs':         '🔧',
        'Cleaning & Household': '🧹',
        'Errands & Delivery':   '📦',
        'Personal Care':        '💆',
        'Food & Events':        '🍽️',
        'Digital & Skills':     '💻',
        'Other':                '✨',
    };

    // Expose globally so other code can read groups (e.g., categories.html)
    window.WMCategories = { LIST: CATEGORIES, GROUPS: PARENT_ORDER, ICONS: PARENT_ICONS, byKey: function(k){ return CATEGORIES.find(c => c.key === k); } };

    // --- Inject styles (once) ---------------------------------------------
    function injectStyles() {
        if (document.getElementById('wm-cat-picker-styles')) return;
        const css = `
.wm-cat-picker { position: relative; width: 100%; }
.wm-cat-input-wrap { position: relative; }
.wm-cat-input {
    width: 100%; padding: 12px 40px 12px 14px; font-size: 1rem;
    border: 1.5px solid var(--border, #e2e8f0); border-radius: 10px;
    background: var(--surface, var(--bg-card, #fff)); color: var(--text, #0f172a);
    transition: border-color .2s, box-shadow .2s;
    box-sizing: border-box;
}
.wm-cat-input:focus {
    outline: none; border-color: var(--primary, #6366f1);
    box-shadow: 0 0 0 3px rgba(99, 102, 241, 0.12);
}
.wm-cat-chevron {
    position: absolute; right: 14px; top: 50%; transform: translateY(-50%);
    color: var(--gray, #64748b); pointer-events: none; font-size: 12px; transition: transform .2s;
}
.wm-cat-picker.open .wm-cat-chevron { transform: translateY(-50%) rotate(180deg); }
.wm-cat-clear {
    position: absolute; right: 36px; top: 50%; transform: translateY(-50%);
    background: none; border: none; color: var(--gray, #94a3b8); cursor: pointer;
    font-size: 16px; padding: 4px; display: none; line-height: 1;
}
.wm-cat-picker.has-value .wm-cat-clear { display: block; }
.wm-cat-panel {
    position: absolute; top: calc(100% + 6px); left: 0; right: 0; z-index: 1050;
    max-height: 320px; overflow-y: auto;
    background: var(--surface, var(--bg-card, #fff)); color: var(--text, #0f172a);
    border: 1px solid var(--border, #e2e8f0); border-radius: 12px;
    box-shadow: 0 12px 32px rgba(15, 23, 42, 0.12);
    display: none; padding: 6px 0;
}
.wm-cat-picker.open .wm-cat-panel { display: block; }
.wm-cat-group-title {
    padding: 8px 14px 4px; font-size: 0.72rem; font-weight: 700;
    color: var(--gray, #64748b); text-transform: uppercase; letter-spacing: 0.06em;
    user-select: none;
}
.wm-cat-option {
    display: flex; align-items: center; gap: 10px;
    padding: 10px 14px; font-size: 0.95rem; cursor: pointer;
    color: var(--text, #0f172a); transition: background .12s;
}
.wm-cat-option:hover, .wm-cat-option.active {
    background: rgba(99, 102, 241, 0.10);
}
.wm-cat-option.selected { background: rgba(99, 102, 241, 0.16); font-weight: 600; }
.wm-cat-option .wm-cat-icon { font-size: 1.1rem; flex-shrink: 0; }
.wm-cat-option .wm-cat-label { flex: 1; }
.wm-cat-option .wm-cat-parent {
    font-size: 0.72rem; color: var(--gray, #94a3b8);
    background: rgba(99,102,241,.08); padding: 2px 8px; border-radius: 999px;
}
.wm-cat-empty { padding: 16px 14px; text-align: center; color: var(--gray, #64748b); font-size: 0.9rem; }
[data-theme="dark"] .wm-cat-input { background: var(--surface, #141a33) !important; color: var(--text, #e7eaf2); border-color: var(--border, #23284a); }
[data-theme="dark"] .wm-cat-panel { background: var(--surface, #141a33); border-color: var(--border, #23284a); box-shadow: 0 12px 32px rgba(0,0,0,.5); }
[data-theme="dark"] .wm-cat-option:hover, [data-theme="dark"] .wm-cat-option.active { background: rgba(139, 134, 245, 0.18); }
[data-theme="dark"] .wm-cat-option.selected { background: rgba(139, 134, 245, 0.25); }
[data-theme="dark"] .wm-cat-option .wm-cat-parent { background: rgba(139,134,245,.18); color: #cbd5e1; }

/* Price-range hint banner --------------------------------------------- */
.wm-price-hint {
    margin: -8px 0 18px 0;
    padding: 12px 14px;
    background: linear-gradient(135deg, #eef2ff 0%, #f0f9ff 100%);
    border: 1px solid #c7d2fe;
    border-left: 4px solid #6366f1;
    border-radius: 10px;
    font-size: 0.92rem;
    color: #1e293b;
    line-height: 1.5;
    animation: wmPriceFade .25s ease-out;
}
@keyframes wmPriceFade { from { opacity: 0; transform: translateY(-4px); } to { opacity: 1; transform: none; } }
.wm-price-hint-head { display: flex; align-items: flex-start; gap: 10px; }
.wm-price-icon { font-size: 1.25rem; flex-shrink: 0; line-height: 1.2; }
.wm-price-text { flex: 1; }
.wm-price-text strong { color: #4f46e5; font-weight: 700; }
.wm-price-hint-actions {
    margin-top: 10px;
    display: flex; flex-wrap: wrap; align-items: center; gap: 6px 8px;
}
.wm-price-hint-label { font-size: 0.82rem; color: #64748b; margin-right: 2px; }
.wm-price-chip {
    padding: 5px 12px; font-size: 0.85rem; font-weight: 600;
    background: #fff; color: #4f46e5;
    border: 1px solid #c7d2fe; border-radius: 999px;
    cursor: pointer; transition: all .15s;
}
.wm-price-chip:hover { background: #6366f1; color: #fff; border-color: #6366f1; }
.wm-price-chip.active { background: #4f46e5; color: #fff; border-color: #4f46e5; box-shadow: 0 2px 6px rgba(79,70,229,.3); }
.wm-price-hint-warn {
    margin-top: 8px; font-size: 0.8rem; color: #b45309;
    padding-top: 8px; border-top: 1px dashed #e0e7ff;
}
[data-theme="dark"] .wm-price-hint {
    background: linear-gradient(135deg, rgba(99,102,241,0.12) 0%, rgba(56,189,248,0.10) 100%);
    border-color: rgba(139,134,245,0.35); border-left-color: #8b86f5;
    color: var(--text, #e7eaf2);
}
[data-theme="dark"] .wm-price-text strong { color: #a5b4fc; }
[data-theme="dark"] .wm-price-hint-label { color: #94a3b8; }
[data-theme="dark"] .wm-price-chip {
    background: rgba(255,255,255,0.04); color: #c7d2fe; border-color: rgba(139,134,245,0.4);
}
[data-theme="dark"] .wm-price-chip:hover { background: #6366f1; color: #fff; }
[data-theme="dark"] .wm-price-hint-warn { color: #fbbf24; border-top-color: rgba(139,134,245,0.25); }

/* Distance pricing row -------------------------------------------------- */
.wm-price-distance {
    margin-top: 10px;
    padding: 10px 12px;
    background: rgba(255,255,255,0.6);
    border: 1px dashed #c7d2fe;
    border-radius: 8px;
    font-size: 0.88rem;
    color: #1e293b;
}
.wm-price-distance i { color: #6366f1; margin-right: 6px; }
.wm-price-distance strong { color: #4f46e5; }
.wm-price-formula { color: #64748b; font-size: 0.8rem; margin-left: 4px; }
.wm-price-distance-empty { color: #64748b; font-style: italic; background: rgba(255,255,255,0.4); }
.wm-price-chip-suggest {
    background: #4f46e5 !important; color: #fff !important; border-color: #4f46e5 !important;
    box-shadow: 0 2px 8px rgba(79,70,229,.35);
}
.wm-price-chip-suggest:hover { background: #4338ca !important; border-color: #4338ca !important; }
.wm-drop-fg .wm-drop-hint { font-size: 0.78rem; color: var(--gray, #64748b); font-weight: 400; margin-left: 4px; }
[data-theme="dark"] .wm-price-distance {
    background: rgba(255,255,255,0.04); border-color: rgba(139,134,245,0.35); color: var(--text, #e7eaf2);
}
[data-theme="dark"] .wm-price-distance i { color: #a5b4fc; }
[data-theme="dark"] .wm-price-distance strong { color: #c7d2fe; }
[data-theme="dark"] .wm-price-distance-empty { color: #94a3b8; background: rgba(255,255,255,0.02); }
[data-theme="dark"] .wm-price-formula { color: #94a3b8; }

/* Ola/Rapido-style vehicle chips -------------------------------------- */
.wm-vehicle-row {
    display: flex; gap: 8px; flex-wrap: wrap; margin: 10px 0 8px 0;
}
.wm-vehicle-chip {
    flex: 1 1 110px; min-width: 110px;
    display: flex; flex-direction: column; align-items: center; gap: 2px;
    padding: 10px 8px;
    background: #fff; border: 1.5px solid #e2e8f0; border-radius: 12px;
    cursor: pointer; transition: all .15s ease; font: inherit;
}
.wm-vehicle-chip:hover { border-color: #a5b4fc; transform: translateY(-1px); }
.wm-vehicle-chip.active {
    border-color: #4f46e5; background: linear-gradient(135deg, #eef2ff, #ede9fe);
    box-shadow: 0 4px 12px rgba(79,70,229,.18);
}
.wm-vehicle-icon { font-size: 1.6rem; line-height: 1; }
.wm-vehicle-label { font-size: 0.82rem; font-weight: 600; color: #1e293b; }
.wm-vehicle-amt { font-size: 0.85rem; font-weight: 700; color: #4f46e5; }
.wm-vehicle-amt-mute { color: #64748b; font-weight: 500; font-size: 0.78rem; }
[data-theme="dark"] .wm-vehicle-chip {
    background: rgba(255,255,255,0.04); border-color: rgba(255,255,255,0.12);
}
[data-theme="dark"] .wm-vehicle-chip:hover { border-color: #8b86f5; }
[data-theme="dark"] .wm-vehicle-chip.active {
    background: rgba(139,134,245,0.18); border-color: #8b86f5;
}
[data-theme="dark"] .wm-vehicle-label { color: var(--text, #e7eaf2); }
[data-theme="dark"] .wm-vehicle-amt { color: #c7d2fe; }
[data-theme="dark"] .wm-vehicle-amt-mute { color: #94a3b8; }

/* Inline route preview map -------------------------------------------- */
.wm-route-map {
    margin-top: 10px; height: 180px; border-radius: 12px; overflow: hidden;
    border: 1px solid #e2e8f0; background: #f1f5f9;
}
.wm-route-pin {
    background: transparent; border: 0;
    display: flex; align-items: center; justify-content: center;
    font-size: 1.3rem;
}
.wm-route-pin-pickup i { color: #10b981; }
.wm-route-pin-drop i { color: #ef4444; font-size: 1.6rem; }
[data-theme="dark"] .wm-route-map { border-color: rgba(255,255,255,0.1); background: #0f172a; }

.wm-pickup-map-btn { display: inline-flex; align-items: center; gap: 6px; }

/* Calculate / Recalculate fare buttons -------------------------------- */
.wm-price-calc-btn, .wm-price-recalc {
    display: inline-flex; align-items: center; gap: 6px;
    padding: 8px 14px; font-size: 0.9rem; font-weight: 600;
    background: #fff; color: #4f46e5;
    border: 1.5px solid #4f46e5; border-radius: 999px;
    cursor: pointer; transition: all .15s ease;
}
.wm-price-calc-btn:hover, .wm-price-recalc:hover {
    background: #4f46e5; color: #fff;
}
.wm-price-recalc {
    background: transparent; color: #6366f1; border-color: #c7d2fe;
    padding: 6px 10px; font-size: 0.82rem;
}
.wm-price-recalc:hover { background: #eef2ff; color: #4338ca; }
.wm-price-distance-error {
    color: #b91c1c !important; background: #fee2e2 !important;
    border-color: #fca5a5 !important; font-style: normal !important;
}
.wm-price-distance-error i { color: #dc2626 !important; }
[data-theme="dark"] .wm-price-calc-btn,
[data-theme="dark"] .wm-price-recalc {
    background: rgba(255,255,255,0.04); color: #c7d2fe; border-color: #8b86f5;
}
[data-theme="dark"] .wm-price-calc-btn:hover,
[data-theme="dark"] .wm-price-recalc:hover { background: #8b86f5; color: #0f172a; }
[data-theme="dark"] .wm-price-distance-error {
    background: rgba(220,38,38,0.15) !important; color: #fca5a5 !important; border-color: rgba(220,38,38,0.4) !important;
}

/* Pick-on-map button + modal ------------------------------------------- */
.wm-drop-map-btn {
    display: inline-flex; align-items: center; gap: 6px;
}
.wm-mappicker-overlay {
    position: fixed; inset: 0; background: rgba(15,23,42,0.65);
    z-index: 99999; display: flex; align-items: center; justify-content: center;
    padding: 16px; animation: wmPriceFade .18s ease-out;
}
.wm-mappicker-modal {
    width: 100%; max-width: 720px; max-height: 92vh;
    background: var(--surface, #fff); color: var(--text, #0f172a);
    border-radius: 14px; box-shadow: 0 20px 60px rgba(0,0,0,.4);
    display: flex; flex-direction: column; overflow: hidden;
}
.wm-mappicker-head {
    padding: 14px 18px; border-bottom: 1px solid var(--border, #e2e8f0);
    display: flex; align-items: center; justify-content: space-between;
}
.wm-mappicker-head h3 { margin: 0; font-size: 1.05rem; font-weight: 600; }
.wm-mappicker-close {
    background: transparent; border: 0; font-size: 1.6rem; line-height: 1;
    color: var(--text, #0f172a); cursor: pointer; padding: 0 6px;
}
.wm-mappicker-body { padding: 12px 14px; display: flex; flex-direction: column; gap: 10px; min-height: 0; }
.wm-mappicker-search { display: flex; gap: 6px; position: relative; z-index: 1100; }
.wm-mappicker-search-box { position: relative; flex: 1; z-index: 1100; }
.wm-mappicker-search input {
    width: 100%; padding: 10px 14px; font-size: 0.95rem;
    border: 1.5px solid var(--border, #e2e8f0); border-radius: 10px;
    background: var(--bg, #fff); color: var(--text, #0f172a);
    box-sizing: border-box; transition: border-color .15s ease, box-shadow .15s ease;
}
.wm-mappicker-search input:focus {
    outline: none; border-color: #6366f1;
    box-shadow: 0 0 0 3px rgba(99,102,241,0.15);
}
.wm-mappicker-results {
    position: absolute; left: 0; right: 0; top: calc(100% + 6px);
    background: var(--surface, #fff); border: 1px solid var(--border, #e2e8f0);
    border-radius: 12px; box-shadow: 0 12px 36px rgba(0,0,0,.22);
    max-height: 320px; overflow-y: auto;
    z-index: 1200;  /* must beat Leaflet panes (max 700) and controls (1000) */
    display: none;
}
.wm-mappicker-results.open { display: block; }
.wm-mappicker-result {
    display: flex; align-items: flex-start; gap: 10px;
    width: 100%; padding: 10px 12px; text-align: left;
    background: transparent; border: 0; border-bottom: 1px solid var(--border, #f1f5f9);
    cursor: pointer; font-size: 0.92rem; color: var(--text, #0f172a);
}
.wm-mappicker-result:last-child { border-bottom: 0; }
.wm-mappicker-result:hover { background: var(--bg, #f8fafc); }
.wm-mappicker-result i { color: #ef4444; margin-top: 2px; flex-shrink: 0; }
.wm-mappicker-result-text { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
.wm-mappicker-result-text strong { font-weight: 600; line-height: 1.3; }
.wm-mappicker-result-text small { color: var(--gray, #64748b); font-size: 0.78rem; line-height: 1.3; }
.wm-mappicker-result-dist {
    flex-shrink: 0; align-self: center;
    font-size: 0.72rem; font-weight: 600; color: #4f46e5;
    background: #eef2ff; border-radius: 999px; padding: 3px 8px;
    white-space: nowrap;
}
.wm-mappicker-result-empty { padding: 14px; text-align: center; color: var(--gray, #64748b); font-size: 0.9rem; line-height: 1.5; }
.wm-mappicker-result-empty small { display: block; margin-top: 4px; font-size: 0.8rem; opacity: 0.85; }
.wm-mappicker-result-empty .fa-spinner { color: #6366f1; margin-right: 6px; }
[data-theme="dark"] .wm-mappicker-result-dist { background: rgba(139,134,245,0.18); color: #c7d2fe; }
[data-theme="dark"] .wm-mappicker-results { background: var(--surface, #141a33); }
[data-theme="dark"] .wm-mappicker-result { color: var(--text, #e7eaf2); border-bottom-color: rgba(255,255,255,0.06); }
[data-theme="dark"] .wm-mappicker-result:hover { background: rgba(139,134,245,0.15); }
.wm-mappicker-search button {
    padding: 9px 14px; border: 1px solid var(--border, #e2e8f0);
    background: var(--surface, #fff); color: var(--text, #0f172a);
    border-radius: 8px; cursor: pointer;
}
.wm-mappicker-search button:hover { background: var(--primary, #6366f1); color: #fff; border-color: var(--primary, #6366f1); }
.wm-mappicker-map {
    width: 100%; height: 380px; min-height: 380px; flex: 0 0 380px;
    border-radius: 12px; overflow: hidden; border: 1px solid var(--border, #e2e8f0);
    position: relative; z-index: 0;  /* creates a stacking context so Leaflet panes stay below the search dropdown */
}
.wm-mappicker-addr {
    background: var(--bg, #f8fafc); padding: 10px 12px; border-radius: 10px;
    font-size: 0.88rem; line-height: 1.4; word-break: break-word;
    border: 1px solid var(--border, #e2e8f0);
}
.wm-mappicker-addr i { color: #ef4444; margin-right: 6px; }
.wm-mappicker-foot {
    padding: 12px 18px; border-top: 1px solid var(--border, #e2e8f0);
    display: flex; justify-content: flex-end; gap: 8px;
}
.wm-mappicker-foot button {
    padding: 9px 18px; border-radius: 8px; font-size: 0.95rem; font-weight: 600;
    cursor: pointer; transition: all .15s;
}
.wm-mappicker-cancel { background: transparent; border: 1px solid var(--border, #cbd5e1); color: var(--text, #0f172a); }
.wm-mappicker-cancel:hover { background: var(--bg, #f1f5f9); }
.wm-mappicker-confirm { background: #6366f1; color: #fff; border: 1px solid #6366f1; }
.wm-mappicker-confirm:hover:not(:disabled) { background: #4f46e5; border-color: #4f46e5; }
.wm-mappicker-confirm:disabled { opacity: .5; cursor: not-allowed; }
@media (max-width: 600px) {
    .wm-mappicker-map { height: 280px; }
}
[data-theme="dark"] .wm-mappicker-modal { background: var(--surface, #141a33); }
[data-theme="dark"] .wm-mappicker-search input,
[data-theme="dark"] .wm-mappicker-search button,
[data-theme="dark"] .wm-mappicker-addr { background: rgba(255,255,255,0.04); }
`;
        const style = document.createElement('style');
        style.id = 'wm-cat-picker-styles';
        style.textContent = css;
        document.head.appendChild(style);
    }

    // --- Fuzzy/keyword search ---------------------------------------------
    function searchCategories(query) {
        const q = (query || '').trim().toLowerCase();
        if (!q) return null; // null = show grouped default
        const tokens = q.split(/\s+/).filter(Boolean);
        const results = [];
        for (const c of CATEGORIES) {
            const haystack = (c.label + ' ' + c.parent + ' ' + (c.keywords || []).join(' ')).toLowerCase();
            let score = 0;
            for (const t of tokens) {
                if (c.label.toLowerCase().startsWith(t)) score += 10;
                else if (c.label.toLowerCase().includes(t)) score += 6;
                if (haystack.includes(t)) score += 3;
            }
            if (score > 0) results.push({ c, score });
        }
        results.sort((a, b) => b.score - a.score);
        return results.map(r => r.c);
    }

    // --- Build the picker UI for a given <select> -------------------------
    function enhance(selectEl) {
        if (!selectEl || selectEl.dataset.wmEnhanced === '1') return;
        if (selectEl.tagName !== 'SELECT') return;
        selectEl.dataset.wmEnhanced = '1';

        // Read existing option keys to filter our master list (so we respect
        // page-specific subsets — e.g., filterCategory has "All Categories")
        const existingKeys = Array.from(selectEl.options).map(o => o.value);
        const isFilter = existingKeys.includes('all'); // browse filter

        // Build the picker container
        const picker = document.createElement('div');
        picker.className = 'wm-cat-picker';

        const inputWrap = document.createElement('div');
        inputWrap.className = 'wm-cat-input-wrap';

        const input = document.createElement('input');
        input.type = 'text';
        input.className = 'wm-cat-input';
        input.autocomplete = 'off';
        input.spellcheck = false;
        input.placeholder = isFilter ? 'All categories — type to search…' : 'Type or select a category (e.g. "fix tap")';
        input.setAttribute('role', 'combobox');
        input.setAttribute('aria-expanded', 'false');
        input.setAttribute('aria-autocomplete', 'list');

        const clearBtn = document.createElement('button');
        clearBtn.type = 'button';
        clearBtn.className = 'wm-cat-clear';
        clearBtn.innerHTML = '&times;';
        clearBtn.setAttribute('aria-label', 'Clear selection');

        const chevron = document.createElement('span');
        chevron.className = 'wm-cat-chevron';
        chevron.innerHTML = '▼';

        const panel = document.createElement('div');
        panel.className = 'wm-cat-panel';
        panel.setAttribute('role', 'listbox');

        inputWrap.appendChild(input);
        inputWrap.appendChild(clearBtn);
        inputWrap.appendChild(chevron);
        picker.appendChild(inputWrap);
        picker.appendChild(panel);

        // Hide native select but keep it in DOM for form/JS reads
        selectEl.style.display = 'none';
        selectEl.setAttribute('aria-hidden', 'true');
        selectEl.tabIndex = -1;
        selectEl.parentNode.insertBefore(picker, selectEl);

        // Helper: get the visible categories list (respects existing options)
        function visibleCategories() {
            return CATEGORIES.filter(c => existingKeys.includes(c.key));
        }

        // Render panel
        function render(results) {
            panel.innerHTML = '';
            const list = results || visibleCategories();
            if (!list.length) {
                panel.innerHTML = '<div class="wm-cat-empty">No matching categories. Try different words or pick "Other".</div>';
                return;
            }

            if (results) {
                // Search mode: flat list with parent badge
                list.forEach((c, idx) => {
                    panel.appendChild(buildOption(c, idx, true));
                });
            } else {
                // Default mode: grouped by parent
                let idx = 0;
                if (isFilter) {
                    const all = document.createElement('div');
                    all.className = 'wm-cat-option';
                    all.dataset.value = 'all';
                    all.dataset.idx = String(idx++);
                    all.innerHTML = '<span class="wm-cat-icon">🌐</span><span class="wm-cat-label">All Categories</span>';
                    all.addEventListener('mousedown', (e) => { e.preventDefault(); selectValue('all', 'All Categories'); });
                    panel.appendChild(all);
                }
                for (const parent of PARENT_ORDER) {
                    const inGroup = list.filter(c => c.parent === parent);
                    if (!inGroup.length) continue;
                    const title = document.createElement('div');
                    title.className = 'wm-cat-group-title';
                    title.textContent = (PARENT_ICONS[parent] || '') + ' ' + parent;
                    panel.appendChild(title);
                    for (const c of inGroup) {
                        panel.appendChild(buildOption(c, idx++, false));
                    }
                }
            }
        }

        function buildOption(c, idx, showParent) {
            const opt = document.createElement('div');
            opt.className = 'wm-cat-option';
            opt.dataset.value = c.key;
            opt.dataset.idx = String(idx);
            opt.setAttribute('role', 'option');
            const icon = c.icon || (c.parent && PARENT_ICONS[c.parent]) || '•';
            opt.innerHTML = `<span class="wm-cat-icon">${icon}</span><span class="wm-cat-label">${c.label}</span>` +
                (showParent ? `<span class="wm-cat-parent">${c.parent}</span>` : '');
            if (selectEl.value === c.key) opt.classList.add('selected');
            // mousedown so blur on input doesn't fire first
            opt.addEventListener('mousedown', (e) => { e.preventDefault(); selectValue(c.key, c.label); });
            return opt;
        }

        function selectValue(key, label) {
            selectEl.value = key;
            input.value = label;
            picker.classList.toggle('has-value', !!key && key !== 'all');
            close();
            selectEl.dispatchEvent(new Event('change', { bubbles: true }));
            selectEl.dispatchEvent(new Event('input', { bubbles: true }));
        }

        function open() {
            picker.classList.add('open');
            input.setAttribute('aria-expanded', 'true');
            // If user just opened with no query, show grouped list
            if (!input.value || input.value === labelFor(selectEl.value)) {
                render(null);
            } else {
                render(searchCategories(input.value));
            }
        }
        function close() {
            picker.classList.remove('open');
            input.setAttribute('aria-expanded', 'false');
            // Reset input to current label if user typed but didn't pick
            const currentLabel = labelFor(selectEl.value);
            if (input.value !== currentLabel) input.value = currentLabel;
        }
        function labelFor(key) {
            if (!key) return '';
            if (key === 'all') return 'All Categories';
            const c = CATEGORIES.find(x => x.key === key);
            return c ? c.label : '';
        }

        // Initial sync from select
        input.value = labelFor(selectEl.value);
        picker.classList.toggle('has-value', !!selectEl.value && selectEl.value !== 'all');

        // Events
        input.addEventListener('focus', open);
        input.addEventListener('click', open);
        input.addEventListener('input', () => {
            picker.classList.add('open');
            const q = input.value.trim();
            if (!q) {
                // Clear selection & show all
                selectEl.value = '';
                picker.classList.remove('has-value');
                render(null);
            } else {
                render(searchCategories(q));
            }
        });
        input.addEventListener('keydown', (e) => {
            const opts = panel.querySelectorAll('.wm-cat-option');
            const active = panel.querySelector('.wm-cat-option.active');
            let idx = active ? Number(active.dataset.idx) : -1;
            if (e.key === 'ArrowDown') {
                e.preventDefault();
                if (!picker.classList.contains('open')) open();
                idx = Math.min(idx + 1, opts.length - 1);
                opts.forEach(o => o.classList.remove('active'));
                if (opts[idx]) { opts[idx].classList.add('active'); opts[idx].scrollIntoView({ block: 'nearest' }); }
            } else if (e.key === 'ArrowUp') {
                e.preventDefault();
                idx = Math.max(idx - 1, 0);
                opts.forEach(o => o.classList.remove('active'));
                if (opts[idx]) { opts[idx].classList.add('active'); opts[idx].scrollIntoView({ block: 'nearest' }); }
            } else if (e.key === 'Enter') {
                if (active) {
                    e.preventDefault();
                    const val = active.dataset.value;
                    const lbl = active.querySelector('.wm-cat-label').textContent;
                    selectValue(val, lbl);
                }
            } else if (e.key === 'Escape') {
                close();
                input.blur();
            }
        });
        clearBtn.addEventListener('click', () => {
            selectValue(isFilter ? 'all' : '', isFilter ? 'All Categories' : '');
            input.focus();
        });

        // Close on outside click
        document.addEventListener('mousedown', (e) => {
            if (!picker.contains(e.target)) close();
        });

        // If something else changes the underlying select (e.g., editTask
        // populates it from a saved task), reflect that in the input.
        const observer = new MutationObserver(() => {
            input.value = labelFor(selectEl.value);
            picker.classList.toggle('has-value', !!selectEl.value && selectEl.value !== 'all');
        });
        observer.observe(selectEl, { attributes: true, attributeFilter: ['value'] });
        // Also catch programmatic value changes (not always seen by observer)
        const origSet = Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, 'value');
        if (origSet && origSet.configurable !== false) {
            // We can't override prototype safely; rely on a periodic sync via
            // 'focus' / 'change' instead.
        }
        selectEl.addEventListener('change', () => {
            input.value = labelFor(selectEl.value);
            picker.classList.toggle('has-value', !!selectEl.value && selectEl.value !== 'all');
        });
    }

    // --- Auto-init on load -------------------------------------------------
    function autoInit() {
        injectStyles();
        const ids = ['modalTaskCategory', 'editTaskCategory', 'filterCategory'];
        ids.forEach(id => {
            const el = document.getElementById(id);
            if (el) enhance(el);
        });
        // Wire description templates (post-task + edit-task forms)
        wireTemplate('modalTaskCategory', 'modalTaskDescription');
        wireTemplate('editTaskCategory',  'editTaskDescription');
        // Wire price-range suggestions (post-task + edit-task forms)
        wirePriceHint('modalTaskCategory', { budgetInputId: 'customBudget', pickupInputId: 'modalTaskLocation', applyBudget: true });
        wirePriceHint('editTaskCategory',  { applyBudget: false });
    }

    // --- Description templates --------------------------------------------
    // Prompt-style placeholders that pre-fill the description textarea when
    // the user picks a category. Helps avoid the "Need plumber" problem.
    const TEMPLATES = {
        plumbing: [
            'What needs fixing? (e.g., leaking tap, clogged drain, broken flush)',
            'Where is the issue located? (kitchen / bathroom / outside)',
            'How long has the problem existed?',
            'Do you have spare parts, or should the tasker bring them?',
        ],
        electrician: [
            'What is the electrical issue? (no power, faulty switch, fan not working, etc.)',
            'Which area / room is affected?',
            'Is there a complete power outage or partial?',
            'Any specific brand of switch / fitting required?',
        ],
        carpentry: [
            'What needs to be built or repaired? (door, window, furniture, shelf...)',
            'Material preference (wood type / plywood / MDF)?',
            'Approximate dimensions if known?',
            'Should the tasker bring tools and materials?',
        ],
        painting: [
            'Which area needs painting? (1 room / full house / exterior wall)',
            'Approximate square feet, if known',
            'Type of paint preferred (emulsion / distemper / enamel)',
            'Will you supply paint, or should the tasker?',
        ],
        repair: [
            'What item needs repair? (AC, fridge, washing machine, microwave, etc.)',
            'Brand and model, if known',
            'What exactly is wrong with it?',
            'Is it under warranty?',
        ],
        vehicle: [
            'Vehicle type and model (car / bike / scooter)',
            'What service is needed? (wash, puncture, battery, full service)',
            'Where should it be done? (your location / workshop)',
            'Any specific issue you have noticed?',
        ],
        household: [
            'What chores need doing? (dishes, dusting, mopping, full cleaning)',
            'How many rooms / size of home?',
            'How long do you expect it will take?',
            'Any equipment / supplies provided?',
        ],
        cleaning: [
            'Type of cleaning needed (deep clean, sofa, bathroom, kitchen, full home)',
            'Size of area in sq.ft. or rooms',
            'Any pets / specific concerns?',
            'Will you provide supplies, or should the tasker?',
        ],
        laundry: [
            'How many items / kg of clothes?',
            'Wash only, or wash + iron + fold?',
            'Any delicate items needing special care?',
            'Pickup and drop required?',
        ],
        gardening: [
            'What work is needed? (mowing, trimming, planting, weeding)',
            'Size of the area (sq.ft. or describe)',
            'Do you have tools, or should the tasker bring them?',
            'Any specific plants to handle carefully?',
        ],
        waste: [
            'What kind of waste? (household garbage, e-waste, scrap, construction debris)',
            'Approximate quantity (bags / kg / load)',
            'Pickup floor / accessibility (lift available?)',
            'How frequently — one-time or recurring?',
        ],
        moving: [
            'What needs to be moved? (full home / few items / office)',
            'Pickup floor and drop floor — is there an elevator?',
            'Approximate distance between locations',
            'Do you need the tasker to bring a vehicle and packing material?',
        ],
        delivery: [
            'What item needs to be delivered? (size / weight)',
            'Pickup address / area',
            'Drop address / area',
            'Any specific time window?',
        ],
        transport: [
            'Pickup point and drop point',
            'How many people / luggage?',
            'Preferred vehicle type (auto / mini / sedan)',
            'Date and time required',
        ],
        shopping: [
            'What needs to be bought? (list of items)',
            'Where to buy from? (specific shop / any)',
            'Approximate budget',
            'Where to deliver after purchase?',
        ],
        petcare: [
            'What kind of pet and breed?',
            'Service needed (walk, grooming, feeding, sitting, vet visit)',
            'Duration / frequency',
            'Any medical conditions or special instructions?',
        ],
        beauty: [
            'Service needed (haircut, makeup, manicure, facial, threading, spa, etc.)',
            'At-home or salon visit?',
            'Date and time preferred',
            'Any product preferences / allergies?',
        ],
        babysitting: [
            'Age of the child / children, and how many',
            'Duration of sitting required (hours / overnight)',
            'Any specific tasks (feeding, study help, pickup from school)?',
            'Any allergies or medical needs to know?',
        ],
        eldercare: [
            'Age and any medical conditions to be aware of',
            'Type of help needed (companionship, mobility, medication, meals)',
            'How many hours / which days?',
            'Any specific language / gender preference for the carer?',
        ],
        fitness: [
            'Type of training (yoga, gym, zumba, personal trainer)',
            'Your fitness goals (weight loss, strength, flexibility)',
            'Preferred days and time slot',
            'At-home or at a center?',
        ],
        cooking: [
            'Cuisine and number of meals / people',
            'Any dietary restrictions (veg / non-veg / Jain / no onion-garlic)',
            'Will ingredients be provided or should the tasker source them?',
            'One-time or recurring (e.g., daily tiffin)?',
        ],
        catering: [
            'Type of event and number of guests',
            'Date, time and venue',
            'Cuisine / menu preference',
            'Any dietary restrictions or allergies?',
        ],
        eventhelp: [
            'What kind of event? (birthday, wedding, corporate, party)',
            'How many helpers needed and for what tasks?',
            'Date, time and venue',
            'Any setup / decoration / hosting requirements?',
        ],
        photography: [
            'Type of shoot (wedding, portrait, event, product, food)',
            'Date, time and location',
            'Number of hours / final deliverables (edited photos / video)?',
            'Any reference style or specific shots wanted?',
        ],
        tutoring: [
            'Subject and class / level (e.g., Class 10 Math, IELTS speaking)',
            'How many hours per week / how often?',
            'Online or in-person?',
            'Specific topics or syllabus to cover?',
        ],
        techsupport: [
            'Device / software involved (laptop, phone, WiFi router, printer)',
            'What is the exact issue?',
            'Brand / model and OS, if known',
            'Have you tried any fixes already?',
        ],
        freelance: [
            'Type of work (logo, website, content writing, video editing, etc.)',
            'Brief on what you want and references / examples',
            'Deadline',
            'Budget range, if any',
        ],
        tailoring: [
            'What needs to be stitched / altered? (blouse, kurta, trousers, dress)',
            'Quantity and current measurements / fitting issue',
            'Material — provided by you or to be sourced?',
            'When do you need it ready?',
        ],
        other: [
            'What is the task in detail?',
            'Where does it need to be done?',
            'How long do you think it will take?',
            'Any specific tools, skills or materials required?',
        ],
    };

    function buildTemplateText(key) {
        const items = TEMPLATES[key];
        if (!items || !items.length) return '';
        // Each question gets an "Answer:" line below it so the user can fill
        // in their reply. They can still add free-form details at the bottom.
        const blocks = items.map((q, i) => 'Q' + (i + 1) + '. ' + q + '\nA: ');
        blocks.push('Additional details (optional):\n');
        return blocks.join('\n\n');
    }

    function wireTemplate(selectId, textareaId) {
        const sel = document.getElementById(selectId);
        const ta  = document.getElementById(textareaId);
        if (!sel || !ta) return;
        if (sel.dataset.wmTplWired === '1') return;
        sel.dataset.wmTplWired = '1';

        const apply = () => {
            const key = sel.value;
            if (!key || key === 'all') return;
            const tpl = buildTemplateText(key);
            if (!tpl) return;
            const current = (ta.value || '').trim();
            const lastTpl = ta.dataset.wmLastTpl || '';
            // Only overwrite if textarea is empty OR still holds the previous template
            if (!current || current === lastTpl.trim()) {
                ta.value = tpl;
                ta.dataset.wmLastTpl = tpl;
                // Notify any listeners (char counters etc.)
                ta.dispatchEvent(new Event('input', { bubbles: true }));
            }
            // Update placeholder always (visible if user clears the textarea)
            ta.placeholder = tpl;
        };

        sel.addEventListener('change', apply);
        // Apply once on load if a category is already selected (edit form)
        if (sel.value && sel.value !== 'all') apply();
    }

    // --- Price range suggestions ------------------------------------------
    // Typical Indian market base-labour ranges (INR) per category.
    // {low, high} → "Most users pay between ₹low and ₹high".
    // {min} → minimum the platform should accept (used to flag unrealistic posts).
    const PRICE_RANGES = {
        plumbing:    { low: 200, high: 600,  min: 150 },
        electrician: { low: 250, high: 700,  min: 150 },
        carpentry:   { low: 300, high: 900,  min: 200 },
        painting:    { low: 500, high: 2500, min: 300 },
        repair:      { low: 300, high: 1200, min: 200 },
        vehicle:     { low: 200, high: 800,  min: 150 },
        household:   { low: 150, high: 500,  min: 100 },
        cleaning:    { low: 300, high: 1500, min: 200 },
        laundry:     { low: 100, high: 400,  min: 100 },
        gardening:   { low: 300, high: 1000, min: 200 },
        waste:       { low: 150, high: 500,  min: 100 },
        moving:      { low: 800, high: 3500, min: 500 },
        delivery:    { low: 100, high: 400,  min: 100 },
        transport:   { low: 150, high: 800,  min: 100 },
        shopping:    { low: 150, high: 500,  min: 100 },
        petcare:     { low: 200, high: 700,  min: 150 },
        beauty:      { low: 300, high: 1500, min: 200 },
        babysitting: { low: 200, high: 800,  min: 150 },
        eldercare:   { low: 300, high: 1200, min: 200 },
        fitness:     { low: 300, high: 1200, min: 200 },
        cooking:     { low: 250, high: 1000, min: 200 },
        catering:    { low: 1500, high: 8000, min: 500 },
        eventhelp:   { low: 500, high: 3000, min: 300 },
        photography: { low: 1000, high: 5000, min: 500 },
        tutoring:    { low: 200, high: 800,  min: 150 },
        techsupport: { low: 200, high: 800,  min: 150 },
        freelance:   { low: 300, high: 3000, min: 150 },
        tailoring:   { low: 150, high: 700,  min: 100 },
        other:       { low: 200, high: 800,  min: 100 },
    };

    function getUserCity() {
        try {
            const u = window.currentUser;
            if (u && u.city) return String(u.city).trim();
            const stored = localStorage.getItem('userCity') || localStorage.getItem('city');
            if (stored) return stored;
        } catch (e) {}
        return 'your area';
    }

    function fmtRupee(n) { return '₹' + Number(n).toLocaleString('en-IN'); }

    // --- Distance-based pricing -------------------------------------------
    // Per-km labour rate (₹) + base fare for travel-based categories.
    // total = base + perKm × distance, clamped to [low, high] of category.
    const DISTANCE_PRICING = {
        transport: { base: 50,  perKm: 15, label: 'Pick & Drop' },
        delivery:  { base: 40,  perKm: 20, label: 'Delivery' },
        moving:    { base: 500, perKm: 40, label: 'Moving & Packing' },
    };

    // Ola/Rapido-style vehicle classes with per-km fare and avg speed (km/h).
    const VEHICLES = {
        bike:  { key: 'bike',  label: 'Bike',  icon: '🏍️', base: 30,  perKm: 8,  speed: 28 },
        auto:  { key: 'auto',  label: 'Auto',  icon: '🛺', base: 50,  perKm: 15, speed: 22 },
        mini:  { key: 'mini',  label: 'Mini',  icon: '🚗', base: 80,  perKm: 18, speed: 30 },
        sedan: { key: 'sedan', label: 'Sedan', icon: '🚙', base: 120, perKm: 22, speed: 32 },
    };
    // Which vehicles to offer per category (transport-style only).
    // NOTE: Pick & Drop (transport) excludes bikes — taskers should be auto/car only
    // for passenger pickup. Bikes remain available for small parcel delivery.
    const VEHICLE_OPTIONS = {
        transport: ['auto', 'mini', 'sedan'],
        delivery:  ['bike', 'auto'],
    };
    const VEHICLE_DEFAULT = { transport: 'auto', delivery: 'bike' };

    // Fetch road-network route via OSRM (free public demo server).
    // Returns { distance(km), duration(min), geometry(GeoJSON LineString) } or null.
    async function wmRoute(a, b) {
        if (!a || !b) return null;
        try {
            const url = 'https://router.project-osrm.org/route/v1/driving/'
                + a.lng + ',' + a.lat + ';' + b.lng + ',' + b.lat
                + '?overview=full&geometries=geojson';
            const r = await fetch(url);
            const data = await r.json();
            if (data && data.routes && data.routes.length) {
                const rt = data.routes[0];
                return {
                    distance: rt.distance / 1000,
                    duration: rt.duration / 60,
                    geometry: rt.geometry,
                };
            }
        } catch (e) {}
        return null;
    }

    function haversine(a, b) {
        if (!a || !b) return null;
        const R = 6371;
        const toRad = d => d * Math.PI / 180;
        const dLat = toRad(b.lat - a.lat);
        const dLng = toRad(b.lng - a.lng);
        const lat1 = toRad(a.lat), lat2 = toRad(b.lat);
        const x = Math.sin(dLat/2)**2 + Math.sin(dLng/2)**2 * Math.cos(lat1) * Math.cos(lat2);
        return 2 * R * Math.asin(Math.sqrt(x));
    }

    async function wmGeocode(addr, bias) {
        if (!addr || addr.length < 4) return null;
        // Build URL with optional viewbox bias around `bias` coords (~55 km box).
        let url = 'https://nominatim.openstreetmap.org/search?q='
            + encodeURIComponent(addr) + '&format=json&limit=5&countrycodes=in';
        if (bias && typeof bias.lat === 'number' && typeof bias.lng === 'number') {
            const d = 0.5; // ~55 km
            const left = bias.lng - d, right = bias.lng + d;
            const top = bias.lat + d, bottom = bias.lat - d;
            url += '&viewbox=' + left + ',' + top + ',' + right + ',' + bottom + '&bounded=0';
        }
        try {
            const r = await fetch(url, { headers: { 'Accept-Language': 'en' } });
            const data = await r.json();
            if (!data || !data.length) return null;
            // Re-rank by proximity to bias, if provided.
            if (bias && typeof bias.lat === 'number') {
                data.sort((a, b) => {
                    const da = haversine({ lat: parseFloat(a.lat), lng: parseFloat(a.lon) }, bias);
                    const db = haversine({ lat: parseFloat(b.lat), lng: parseFloat(b.lon) }, bias);
                    return da - db;
                });
            }
            return { lat: parseFloat(data[0].lat), lng: parseFloat(data[0].lon) };
        } catch (e) {}
        return null;
    }

    // Inject a "Drop Location" form-group after the pickup field.
    // Returns { input, getCoords, hide, show }.
    function ensureDropField(pickupId) {
        const pickup = document.getElementById(pickupId);
        if (!pickup) return null;
        const pickupFG = pickup.closest('.form-group');
        if (!pickupFG) return null;
        let drop = document.getElementById(pickupId + '_drop');
        let dropFG = drop ? drop.closest('.form-group') : null;
        if (!drop) {
            dropFG = document.createElement('div');
            dropFG.className = 'form-group wm-drop-fg';
            dropFG.innerHTML =
                '<label for="' + pickupId + '_drop"><i class="fas fa-flag-checkered"></i> Drop Location</label>'
              + '<div class="location-input-wrapper">'
              +   '<input type="text" id="' + pickupId + '_drop" placeholder="Where to? (e.g., FC Road, Pune)">'
              +   '<button type="button" class="location-btn wm-drop-map-btn" id="' + pickupId + '_dropMapBtn">'
              +     '<i class="fas fa-map-marked-alt"></i> Pick on Map'
              +   '</button>'
              + '</div>';
            pickupFG.parentNode.insertBefore(dropFG, pickupFG.nextSibling);
            drop = dropFG.querySelector('input');
            drop.dataset.wmDropFor = pickupId;
        }
        return {
            input: drop,
            fg: dropFG,
            mapBtn: document.getElementById(pickupId + '_dropMapBtn'),
            show: () => { dropFG.style.display = ''; },
            hide: () => { dropFG.style.display = 'none'; },
        };
    }

    // Inject a "Pick on Map" button next to the pickup input (alongside the
    // existing "Use My Location" button if present).  Returns the button el.
    function ensurePickupMapBtn(pickupId) {
        const pickup = document.getElementById(pickupId);
        if (!pickup) return null;
        const wrapper = pickup.closest('.location-input-wrapper');
        if (!wrapper) return null;
        let btn = document.getElementById(pickupId + '_pickupMapBtn');
        if (!btn) {
            btn = document.createElement('button');
            btn.type = 'button';
            btn.id = pickupId + '_pickupMapBtn';
            btn.className = 'location-btn wm-pickup-map-btn';
            btn.innerHTML = '<i class="fas fa-map-marked-alt"></i> Pick on Map';
            btn.style.display = 'none';
            wrapper.appendChild(btn);
        }
        return btn;
    }

    // Open a Leaflet map modal for the user to click / drag a pin.
    // Calls onConfirm({ lat, lng, address }) when the user confirms.
    function openMapPicker(opts) {
        opts = opts || {};
        if (typeof L === 'undefined') {
            alert('Map is still loading. Please try again in a moment.');
            return;
        }
        // Remove any prior instance
        const existing = document.getElementById('wmMapPicker');
        if (existing) existing.remove();

        const overlay = document.createElement('div');
        overlay.id = 'wmMapPicker';
        overlay.className = 'wm-mappicker-overlay';
        overlay.innerHTML =
            '<div class="wm-mappicker-modal">'
          +   '<div class="wm-mappicker-head">'
          +     '<h3><i class="fas fa-map-marker-alt"></i> ' + (opts.title || 'Choose Drop Location') + '</h3>'
          +     '<button type="button" class="wm-mappicker-close" aria-label="Close">&times;</button>'
          +   '</div>'
          +   '<div class="wm-mappicker-body">'
          +     '<div class="wm-mappicker-search">'
          +       '<div class="wm-mappicker-search-box">'
          +         '<input type="text" placeholder="Search address or place…" id="wmMapPickerSearch" autocomplete="off">'
          +         '<div class="wm-mappicker-results" id="wmMapPickerResults"></div>'
          +       '</div>'
          +       '<button type="button" id="wmMapPickerSearchBtn"><i class="fas fa-search"></i></button>'
          +       '<button type="button" id="wmMapPickerGps" title="Use my location"><i class="fas fa-crosshairs"></i></button>'
          +     '</div>'
          +     '<div id="wmMapPickerMap" class="wm-mappicker-map"></div>'
          +     '<div class="wm-mappicker-addr">'
          +       '<i class="fas fa-map-marker-alt"></i> '
          +       '<span id="wmMapPickerAddrText">Click on the map or search to drop a pin</span>'
          +     '</div>'
          +   '</div>'
          +   '<div class="wm-mappicker-foot">'
          +     '<button type="button" class="wm-mappicker-cancel">Cancel</button>'
          +     '<button type="button" class="wm-mappicker-confirm" disabled>Confirm Location</button>'
          +   '</div>'
          + '</div>';
        document.body.appendChild(overlay);

        const center = opts.start || { lat: 18.5204, lng: 73.8567 }; // Pune fallback
        const map = L.map('wmMapPickerMap').setView([center.lat, center.lng], opts.start ? 14 : 12);
        L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
            attribution: '© OpenStreetMap', maxZoom: 19
        }).addTo(map);

        let marker = null;
        let chosen = null;
        const addrEl = overlay.querySelector('#wmMapPickerAddrText');
        const confirmBtn = overlay.querySelector('.wm-mappicker-confirm');

        const setMarker = async (lat, lng, skipReverse) => {
            if (!marker) {
                marker = L.marker([lat, lng], { draggable: true }).addTo(map);
                marker.on('dragend', e => {
                    const p = e.target.getLatLng();
                    setMarker(p.lat, p.lng);
                });
            } else {
                marker.setLatLng([lat, lng]);
            }
            chosen = { lat, lng, address: '' };
            confirmBtn.disabled = false;
            if (skipReverse) return;
            addrEl.textContent = 'Looking up address…';
            try {
                const r = await fetch('https://nominatim.openstreetmap.org/reverse?lat=' + lat + '&lon=' + lng + '&format=json',
                    { headers: { 'Accept-Language': 'en' } });
                const d = await r.json();
                chosen.address = d.display_name || (lat.toFixed(5) + ', ' + lng.toFixed(5));
                addrEl.textContent = chosen.address;
            } catch (e) {
                chosen.address = lat.toFixed(5) + ', ' + lng.toFixed(5);
                addrEl.textContent = chosen.address;
            }
        };

        if (opts.start) setMarker(opts.start.lat, opts.start.lng);

        map.on('click', e => setMarker(e.latlng.lat, e.latlng.lng));

        // Force resize after modal animates in
        setTimeout(() => map.invalidateSize(), 250);
        setTimeout(() => map.invalidateSize(), 600);

        const close = () => { try { map.remove(); } catch (e) {} overlay.remove(); };
        overlay.querySelector('.wm-mappicker-close').addEventListener('click', close);
        overlay.querySelector('.wm-mappicker-cancel').addEventListener('click', close);
        overlay.addEventListener('click', e => { if (e.target === overlay) close(); });

        confirmBtn.addEventListener('click', () => {
            if (!chosen) return;
            close();
            if (typeof opts.onConfirm === 'function') opts.onConfirm(chosen);
        });

        // Search — shows a dropdown of top results so user can pick one
        const resultsEl = overlay.querySelector('#wmMapPickerResults');
        const searchInput = overlay.querySelector('#wmMapPickerSearch');

        // Proximity bias point — defaults to opts.start, falls back to map center.
        // Used both for Nominatim viewbox bias AND for sorting results by distance.
        const getBiasPoint = () => {
            if (opts.start && typeof opts.start.lat === 'number') return opts.start;
            const c = map.getCenter();
            return { lat: c.lat, lng: c.lng };
        };

        const fmtKm = (km) => km < 1 ? Math.round(km * 1000) + ' m' : km.toFixed(1) + ' km';

        const renderResults = (data) => {
            if (!data || !data.length) {
                resultsEl.innerHTML = '<div class="wm-mappicker-result-empty">'
                  + '<i class="fas fa-search"></i> No results found.<br>'
                  + '<small>Try a different spelling, add city name, or click on the map below to drop a pin.</small>'
                  + '</div>';
                resultsEl.classList.add('open');
                return;
            }
            const bias = getBiasPoint();
            resultsEl.innerHTML = data.map((d, i) => {
                const name = d.display_name || '';
                const head = name.split(',').slice(0, 2).join(',').trim();
                const tail = name.split(',').slice(2).join(',').trim();
                const lat = parseFloat(d.lat), lng = parseFloat(d.lon);
                const dist = haversine(bias, { lat, lng });
                const distBadge = (dist != null && dist < 200)
                    ? '<span class="wm-mappicker-result-dist">' + fmtKm(dist) + '</span>'
                    : '';
                return '<button type="button" class="wm-mappicker-result" data-i="' + i + '">'
                     +   '<i class="fas fa-map-marker-alt"></i>'
                     +   '<span class="wm-mappicker-result-text">'
                     +     '<strong>' + (head || name) + '</strong>'
                     +     (tail ? '<small>' + tail + '</small>' : '')
                     +   '</span>'
                     +   distBadge
                     + '</button>';
            }).join('');
            resultsEl.classList.add('open');
            resultsEl.querySelectorAll('.wm-mappicker-result').forEach(btn => {
                btn.addEventListener('click', () => {
                    const i = parseInt(btn.dataset.i, 10);
                    const d = data[i];
                    if (!d) return;
                    const lat = parseFloat(d.lat), lng = parseFloat(d.lon);
                    map.setView([lat, lng], 15);
                    setMarker(lat, lng, true);
                    chosen.address = d.display_name;
                    addrEl.textContent = d.display_name;
                    searchInput.value = (d.display_name || '').split(',').slice(0, 2).join(',');
                    resultsEl.classList.remove('open');
                });
            });
        };

        // Build a Nominatim query URL biased toward the given lat/lng.
        // viewbox = ±0.5° (~55 km) around the bias point, bounded=0 lets
        // results outside the box still surface but ranked lower.
        const runQuery = async (q, limit) => {
            const bias = getBiasPoint();
            const dx = 0.5, dy = 0.5; // ~55 km radius
            const vb = (bias.lng - dx) + ',' + (bias.lat + dy) + ',' + (bias.lng + dx) + ',' + (bias.lat - dy);
            const url = 'https://nominatim.openstreetmap.org/search?q=' + encodeURIComponent(q)
                + '&format=json&limit=' + (limit || 8)
                + '&countrycodes=in&addressdetails=0'
                + '&viewbox=' + vb + '&bounded=0';
            try {
                const r = await fetch(url, { headers: { 'Accept-Language': 'en' } });
                let data = await r.json();
                if (!Array.isArray(data)) return [];
                // Re-rank: results near bias point first.  Many Nominatim
                // queries return geographically distant matches first when
                // bounded=0; sort client-side to keep nearby ones at the top.
                data = data.slice(0, limit || 8).map(d => {
                    const lat = parseFloat(d.lat), lng = parseFloat(d.lon);
                    return { d, dist: haversine(bias, { lat, lng }) || 9999 };
                }).sort((a, b) => a.dist - b.dist).map(x => x.d);
                return data;
            } catch (e) { return null; }
        };

        const doSearch = async () => {
            const q = searchInput.value.trim();
            if (q.length < 2) return;
            resultsEl.innerHTML = '<div class="wm-mappicker-result-empty">'
              + '<i class="fas fa-spinner fa-spin"></i> Searching nearby…</div>';
            resultsEl.classList.add('open');
            const data = await runQuery(q, 8);
            if (data === null) {
                resultsEl.innerHTML = '<div class="wm-mappicker-result-empty">'
                  + '<i class="fas fa-exclamation-triangle"></i> Search failed — check your internet, then retry.'
                  + '</div>';
                return;
            }
            renderResults(data);
        };

        // Live (debounced) suggestions while typing.  2-char threshold so
        // short Indian place names like "FC", "MG", "JM" surface quickly.
        let searchTimer = null;
        searchInput.addEventListener('input', () => {
            clearTimeout(searchTimer);
            const q = searchInput.value.trim();
            if (q.length < 2) { resultsEl.classList.remove('open'); return; }
            searchTimer = setTimeout(doSearch, 300);
        });
        searchInput.addEventListener('focus', () => {
            const q = searchInput.value.trim();
            if (q.length >= 2 && resultsEl.innerHTML) resultsEl.classList.add('open');
        });
        overlay.querySelector('#wmMapPickerSearchBtn').addEventListener('click', doSearch);
        searchInput.addEventListener('keydown', e => {
            if (e.key === 'Enter') { e.preventDefault(); doSearch(); }
            else if (e.key === 'Escape') { resultsEl.classList.remove('open'); }
        });
        // Close results when clicking outside the search area
        document.addEventListener('mousedown', function outsideClose(e) {
            if (!overlay.contains(e.target)) return;
            const sb = overlay.querySelector('.wm-mappicker-search-box');
            if (sb && !sb.contains(e.target)) resultsEl.classList.remove('open');
        });

        overlay.querySelector('#wmMapPickerGps').addEventListener('click', () => {
            if (!navigator.geolocation) return;
            navigator.geolocation.getCurrentPosition(p => {
                map.setView([p.coords.latitude, p.coords.longitude], 15);
                setMarker(p.coords.latitude, p.coords.longitude);
            }, () => { addrEl.textContent = 'Could not get GPS location.'; }, { enableHighAccuracy: true, timeout: 8000 });
        });
    }

    function wirePriceHint(selectId, opts) {
        opts = opts || {};
        const sel = document.getElementById(selectId);
        if (!sel) return;
        if (sel.dataset.wmPriceWired === '1') return;
        sel.dataset.wmPriceWired = '1';

        // Find the form-group ancestor of the select to insert the hint after.
        const fg = sel.closest('.form-group') || sel.parentElement;
        if (!fg) return;
        const hint = document.createElement('div');
        hint.className = 'wm-price-hint';
        hint.style.display = 'none';
        // Prefer an explicit slot element (used by the post-task wizard to
        // place the vehicle/fair-price panel on the Budget step).  Fall back
        // to inserting after the category form-row.
        const slot = opts.applyBudget ? document.getElementById('wmPriceHintSlot') : null;
        if (slot) {
            slot.appendChild(hint);
        } else {
            // Place after the form-row (if select is in a row) so it spans full width
            const row = sel.closest('.form-row');
            const anchor = row || fg;
            anchor.parentNode.insertBefore(hint, anchor.nextSibling);
        }

        // Optional drop-location field for distance pricing
        const pickupId = opts.pickupInputId;
        const dropApi = (opts.applyBudget && pickupId) ? ensureDropField(pickupId) : null;
        if (dropApi) dropApi.hide();
        const pickupMapBtn = (opts.applyBudget && pickupId) ? ensurePickupMapBtn(pickupId) : null;

        // Latest known geocoded coords / distance (cached on the hint element)
        let pickupCoords = null;
        let dropCoords   = null;
        let lastDistance = null;       // km (road if route present, else haversine)
        let lastDuration = null;       // minutes (from OSRM, else null)
        let lastRouteGeo = null;       // GeoJSON LineString geometry (or null)
        let selectedVehicle = null;    // selected vehicle key for transport/delivery
        let calculating  = false;      // true while distance/route is being fetched
        let lastError    = null;       // user-friendly error message if calc failed

        const applyValueToBudget = (amt) => {
            const customId = opts.budgetInputId || 'customBudget';
            const budget = document.getElementById(customId);
            if (!budget) return;
            budget.value = amt;
            budget.dispatchEvent(new Event('input', { bubbles: true }));
            try {
                document.querySelectorAll('.budget-option').forEach(o => o.classList.remove('active'));
                if (typeof window.updateTotalBudgetDisplay === 'function') {
                    window.updateTotalBudgetDisplay();
                }
            } catch (e) {}
            budget.focus();
        };

        const update = () => {
            const key = sel.value;
            const range = PRICE_RANGES[key];
            const cat = (window.WMCategories && window.WMCategories.byKey(key)) || null;
            if (!key || key === 'all' || !range) {
                hint.style.display = 'none';
                if (dropApi) dropApi.hide();
                return;
            }
            const distMeta = DISTANCE_PRICING[key];
            // Show drop field + pickup map button only for distance-based categories
            if (dropApi) {
                if (distMeta) dropApi.show(); else dropApi.hide();
            }
            if (pickupMapBtn) {
                pickupMapBtn.style.display = distMeta ? '' : 'none';
            }

            const city  = getUserCity();
            const label = cat ? cat.label : key;
            const icon  = cat ? cat.icon : '💡';
            const lowFmt  = fmtRupee(range.low);
            const highFmt = fmtRupee(range.high);

            // For distance categories, show Ola/Rapido-style pricing UI:
            // header → vehicle chips → distance/ETA row → suggested price → mini map.
            if (distMeta) {
                // Decide effective fare meta — vehicle override (if any) else category default.
                const vehicleKeys = VEHICLE_OPTIONS[key];
                let effMeta = distMeta;
                if (vehicleKeys && vehicleKeys.length) {
                    if (!selectedVehicle || vehicleKeys.indexOf(selectedVehicle) === -1) {
                        selectedVehicle = VEHICLE_DEFAULT[key] || vehicleKeys[0];
                    }
                    try { window.__wmSelectedVehicle = selectedVehicle; } catch (e) {}
                    try { window.__wmSelectedVehicle = selectedVehicle; } catch (e) {}
                    effMeta = VEHICLES[selectedVehicle];
                }

                let html = ''
                    + '<div class="wm-price-hint-head">'
                    +   '<span class="wm-price-icon">' + icon + '</span>'
                    +   '<span class="wm-price-text">'
                    +     '<strong>' + label + '</strong> — choose a vehicle, then set pickup &amp; drop.'
                    +   '</span>'
                    + '</div>';

                // Vehicle chips
                if (vehicleKeys && vehicleKeys.length) {
                    html += '<div class="wm-vehicle-row">';
                    vehicleKeys.forEach(vk => {
                        const v = VEHICLES[vk];
                        let est = '';
                        if (lastDistance != null) {
                            const a = Math.max(range.min, Math.round((v.base + v.perKm * lastDistance) / 10) * 10);
                            est = '<span class="wm-vehicle-amt">' + fmtRupee(a) + '</span>';
                        } else {
                            est = '<span class="wm-vehicle-amt wm-vehicle-amt-mute">' + fmtRupee(v.perKm) + '/km</span>';
                        }
                        html += '<button type="button" class="wm-vehicle-chip'
                             + (vk === selectedVehicle ? ' active' : '')
                             + '" data-veh="' + vk + '">'
                             +   '<span class="wm-vehicle-icon">' + v.icon + '</span>'
                             +   '<span class="wm-vehicle-label">' + v.label + '</span>'
                             +   est
                             + '</button>';
                    });
                    html += '</div>';
                }

                let suggestedAmt = null;
                if (lastDistance != null) {
                    const raw = effMeta.base + effMeta.perKm * lastDistance;
                    suggestedAmt = Math.max(range.min, Math.round(raw / 10) * 10);
                    const speed = effMeta.speed || 25;
                    const etaMin = lastDuration != null
                        ? Math.max(2, Math.round(lastDuration))
                        : Math.max(2, Math.round((lastDistance / speed) * 60));
                    html += '<div class="wm-price-distance">'
                         +    '<i class="fas fa-route"></i> '
                         +    '<strong>' + lastDistance.toFixed(1) + ' km</strong>'
                         +    ' &nbsp;·&nbsp; <i class="far fa-clock"></i> ~' + etaMin + ' min'
                         +    ' &nbsp;·&nbsp; Fair price ≈ <strong>' + fmtRupee(suggestedAmt) + '</strong>'
                         + '</div>';
                } else if (calculating) {
                    html += '<div class="wm-price-distance wm-price-distance-empty">'
                         +    '<i class="fas fa-spinner fa-spin"></i> '
                         +    'Calculating distance &amp; fair price…'
                         + '</div>';
                } else if (lastError) {
                    html += '<div class="wm-price-distance wm-price-distance-empty wm-price-distance-error">'
                         +    '<i class="fas fa-exclamation-triangle"></i> '
                         +    lastError
                         + '</div>';
                } else if (opts.applyBudget) {
                    html += '<div class="wm-price-distance wm-price-distance-empty">'
                         +    '<i class="fas fa-route"></i> '
                         +    'Set pickup &amp; drop (use <i class="fas fa-map-marked-alt"></i> Pick on Map) to see distance, ETA and a fair price.'
                         + '</div>';
                }
                if (opts.applyBudget && suggestedAmt != null) {
                    // Auto-apply suggested price to budget input.
                    try { applyValueToBudget(suggestedAmt); } catch (e) {}
                    html += '<div class="wm-price-hint-actions">'
                         +    '<span class="wm-price-hint-label"><i class="fas fa-check-circle" style="color:#10b981"></i> Applied to your budget:</span>'
                         +    '<strong class="wm-price-chip wm-price-chip-suggest active">' + fmtRupee(suggestedAmt) + '</strong>'
                         +    '<button type="button" class="wm-price-recalc" id="wmPriceRecalc_' + selectId + '">'
                         +      '<i class="fas fa-sync-alt"></i> Recalculate'
                         +    '</button>'
                         + '</div>';
                } else if (opts.applyBudget && !calculating) {
                    // No distance yet — give an explicit button to trigger calculation
                    html += '<div class="wm-price-hint-actions">'
                         +    '<button type="button" class="wm-price-calc-btn" id="wmPriceRecalc_' + selectId + '">'
                         +      '<i class="fas fa-calculator"></i> Calculate fair price'
                         +    '</button>'
                         + '</div>';
                }
                // Mini route preview map placeholder (filled after innerHTML set)
                if (pickupCoords && dropCoords) {
                    html += '<div class="wm-route-map" id="wmRouteMap_' + selectId + '"></div>';
                }
                hint.innerHTML = html;
                hint.style.display = 'block';

                // Wire vehicle chips
                hint.querySelectorAll('.wm-vehicle-chip').forEach(btn => {
                    btn.addEventListener('click', () => {
                        selectedVehicle = btn.dataset.veh;
                        try { window.__wmSelectedVehicle = selectedVehicle; } catch (e) {}
                        update();
                        // If pickup+drop are already set, vehicle change should re-apply
                        // a per-vehicle suggested price (handled by the next update()),
                        // but we also re-run updateTotalBudgetDisplay so service charge
                        // box stays in sync.
                        try {
                            if (typeof window.updateTotalBudgetDisplay === 'function') window.updateTotalBudgetDisplay();
                        } catch (e) {}
                    });
                });
                if (opts.applyBudget) {
                    hint.querySelectorAll('.wm-price-chip').forEach(btn => {
                        btn.addEventListener('click', () => {
                            const amt = parseInt(btn.dataset.amt, 10);
                            if (!isNaN(amt)) applyValueToBudget(amt);
                            hint.querySelectorAll('.wm-price-chip').forEach(b => b.classList.remove('active'));
                            btn.classList.add('active');
                        });
                    });
                    const recalc = document.getElementById('wmPriceRecalc_' + selectId);
                    if (recalc) recalc.addEventListener('click', () => refreshDistance(true));
                }
                // Render mini-map with route line
                const mapDiv = document.getElementById('wmRouteMap_' + selectId);
                if (mapDiv && pickupCoords && dropCoords && typeof L !== 'undefined') {
                    try {
                        const m = L.map(mapDiv, {
                            zoomControl: false,
                            attributionControl: false,
                            dragging: false,
                            scrollWheelZoom: false,
                            doubleClickZoom: false,
                            boxZoom: false,
                            keyboard: false,
                            touchZoom: false,
                        });
                        L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
                            maxZoom: 18,
                        }).addTo(m);
                        const pIcon = L.divIcon({ className: 'wm-route-pin wm-route-pin-pickup', html: '<i class="fas fa-circle-dot"></i>', iconSize: [22, 22], iconAnchor: [11, 11] });
                        const dIcon = L.divIcon({ className: 'wm-route-pin wm-route-pin-drop',   html: '<i class="fas fa-map-marker-alt"></i>', iconSize: [26, 26], iconAnchor: [13, 24] });
                        L.marker([pickupCoords.lat, pickupCoords.lng], { icon: pIcon }).addTo(m);
                        L.marker([dropCoords.lat, dropCoords.lng], { icon: dIcon }).addTo(m);
                        if (lastRouteGeo && lastRouteGeo.coordinates && lastRouteGeo.coordinates.length) {
                            const latlngs = lastRouteGeo.coordinates.map(c => [c[1], c[0]]);
                            L.polyline(latlngs, { color: '#6366f1', weight: 4, opacity: 0.85 }).addTo(m);
                            m.fitBounds(latlngs, { padding: [20, 20] });
                        } else {
                            const latlngs = [[pickupCoords.lat, pickupCoords.lng], [dropCoords.lat, dropCoords.lng]];
                            L.polyline(latlngs, { color: '#6366f1', weight: 3, opacity: 0.7, dashArray: '6 6' }).addTo(m);
                            m.fitBounds(latlngs, { padding: [20, 20] });
                        }
                        setTimeout(() => m.invalidateSize(), 250);
                    } catch (e) { /* ignore map errors */ }
                }
                return;
            }

            // Non-distance categories: show city-range banner + quick-set chips
            let html = ''
                + '<div class="wm-price-hint-head">'
                +   '<span class="wm-price-icon">' + icon + '</span>'
                +   '<span class="wm-price-text">'
                +     'Most posters in <strong>' + city + '</strong> pay '
                +     '<strong>' + lowFmt + ' – ' + highFmt + '</strong> for ' + label + ' tasks.'
                +   '</span>'
                + '</div>';

            if (opts.applyBudget) {
                html += '<div class="wm-price-hint-actions">'
                     +    '<span class="wm-price-hint-label">Quick set:</span>'
                     +    '<button type="button" class="wm-price-chip" data-amt="' + range.low  + '">' + lowFmt  + '</button>'
                     +    '<button type="button" class="wm-price-chip" data-amt="' + Math.round((range.low+range.high)/2) + '">' + fmtRupee(Math.round((range.low+range.high)/2)) + '</button>'
                     +    '<button type="button" class="wm-price-chip" data-amt="' + range.high + '">' + highFmt + '</button>'
                     + '</div>'
                     + '<div class="wm-price-hint-warn">'
                     +   'Posting below ' + fmtRupee(range.min) + ' may not get accepted by any tasker.'
                     + '</div>';
            }
            hint.innerHTML = html;
            hint.style.display = 'block';

            if (opts.applyBudget) {
                hint.querySelectorAll('.wm-price-chip').forEach(btn => {
                    btn.addEventListener('click', () => {
                        const amt = parseInt(btn.dataset.amt, 10);
                        if (!isNaN(amt)) applyValueToBudget(amt);
                        hint.querySelectorAll('.wm-price-chip').forEach(b => b.classList.remove('active'));
                        btn.classList.add('active');
                    });
                });
            }
        };

        // Geocode pickup + drop, fetch road route, then refresh hint
        const refreshDistance = async (forceShow) => {
            if (!dropApi || !DISTANCE_PRICING[sel.value]) return;
            const pickupEl = document.getElementById(pickupId);
            const dropEl   = dropApi.input;
            if (!pickupEl || !dropEl) return;
            const pTxt = (pickupEl.value || '').trim();
            const dTxt = (dropEl.value || '').trim();
            // If neither side has any value at all and user didn't ask for it,
            // skip silently. On forceShow (button click) we always run.
            if (!forceShow && !pTxt && !dTxt
                && !dropApi.pickupCoords && !dropApi.dropCoords
                && !(window.modalTaskCoords && window.modalTaskCoords.lat)) {
                return;
            }
            calculating = true;
            lastError = null;
            update(); // show "Calculating…" state immediately

            // Resolve drop coords FIRST so we can bias pickup geocoding around it.
            try {
                if (dropApi.dropCoords) {
                    dropCoords = dropApi.dropCoords;
                } else if (dTxt) {
                    dropCoords = await wmGeocode(dTxt);
                } else {
                    dropCoords = null;
                }
            } catch (e) { dropCoords = null; }

            // Resolve pickup coords (try GPS / map-pick first, then geocode w/ bias).
            try {
                if (dropApi.pickupCoords) {
                    pickupCoords = dropApi.pickupCoords;
                } else if (window.modalTaskCoords && window.modalTaskCoords.lat) {
                    pickupCoords = window.modalTaskCoords;
                } else if (pTxt) {
                    // First pass: bias around drop if known.
                    pickupCoords = await wmGeocode(pTxt, dropCoords);
                    // Fallback: unbiased lookup.
                    if (!pickupCoords) pickupCoords = await wmGeocode(pTxt);
                } else {
                    pickupCoords = null;
                }
            } catch (e) { pickupCoords = null; }

            // Try OSRM road route; fall back to haversine on failure
            lastRouteGeo = null;
            lastDuration = null;
            if (pickupCoords && dropCoords) {
                const route = await wmRoute(pickupCoords, dropCoords);
                if (route) {
                    lastDistance = route.distance;
                    lastDuration = route.duration;
                    lastRouteGeo = route.geometry;
                } else {
                    lastDistance = haversine(pickupCoords, dropCoords);
                }
            } else {
                lastDistance = null;
                if (forceShow) {
                    const pTxtNow = (document.getElementById(pickupId) || {}).value || '';
                    if (!pickupCoords && !dropCoords) {
                        lastError = 'Set both pickup and drop locations. Use "Use My Location" or "Pick on Map".';
                    } else if (!pickupCoords) {
                        lastError = pTxtNow.trim()
                            ? 'Couldn\'t locate pickup address. Tap "Use My Location" or "Pick on Map" next to the pickup field.'
                            : 'Pickup is empty. Tap "Use My Location" or "Pick on Map" next to the pickup field.';
                    } else {
                        lastError = 'Couldn\'t locate drop address. Tap "Pick on Map" next to the drop field.';
                    }
                }
            }
            calculating = false;
            // Expose distance globally so updateTotalBudgetDisplay() can scale the
            // service charge for distance-based categories (Pick&Drop / Delivery / Moving).
            try { window.__wmLastDistance = lastDistance; } catch (e) {}
            update();
            // Re-render the service-charge box with the new distance-aware charge.
            try {
                if (typeof window.updateTotalBudgetDisplay === 'function') window.updateTotalBudgetDisplay();
            } catch (e) {}
        };

        sel.addEventListener('change', () => {
            lastDistance = null;
            lastDuration = null;
            lastRouteGeo = null;
            selectedVehicle = null;
            try { window.__wmLastDistance = null; window.__wmSelectedVehicle = null; } catch (e) {}
            update();
            try {
                if (typeof window.updateTotalBudgetDisplay === 'function') window.updateTotalBudgetDisplay();
            } catch (e) {}
        });
        // Expose a hook so other code paths (e.g. Use My Location) can ask the
        // distance-based price hint to recompute itself.
        if (opts.applyBudget) {
            try { window.__wmRefreshDistance = () => refreshDistance(); } catch (e) {}
        }
        if (dropApi) {
            dropApi.input.addEventListener('blur', () => {
                // User typed manually — clear any prior map-picked coords
                dropApi.dropCoords = null;
                refreshDistance();
            });
            const pickupEl = document.getElementById(pickupId);
            if (pickupEl) pickupEl.addEventListener('blur', () => {
                // Manual edit clears cached pickup coords
                if (dropApi) dropApi.pickupCoords = null;
                refreshDistance();
            });

            // Wire the drop "Pick on Map" button
            if (dropApi.mapBtn) {
                dropApi.mapBtn.addEventListener('click', () => {
                    // Use pickup coords as proximity bias so search finds places near pickup
                    const start = pickupCoords
                        || (window.modalTaskCoords && window.modalTaskCoords.lat ? window.modalTaskCoords : null);
                    openMapPicker({
                        title: 'Choose Drop Location',
                        start: start,
                        onConfirm: (loc) => {
                            dropApi.input.value = loc.address;
                            dropApi.dropCoords = { lat: loc.lat, lng: loc.lng };
                            refreshDistance(true);
                        }
                    });
                });
            }

            // Wire the pickup "Pick on Map" button
            if (pickupMapBtn) {
                pickupMapBtn.addEventListener('click', () => {
                    const start = pickupCoords
                        || (window.modalTaskCoords && window.modalTaskCoords.lat ? window.modalTaskCoords : null);
                    openMapPicker({
                        title: 'Choose Pickup Location',
                        start: start,
                        onConfirm: (loc) => {
                            const pEl = document.getElementById(pickupId);
                            if (pEl) pEl.value = loc.address;
                            dropApi.pickupCoords = { lat: loc.lat, lng: loc.lng };
                            // Also update global modalTaskCoords so other code paths see it
                            try { window.modalTaskCoords = { lat: loc.lat, lng: loc.lng }; } catch (e) {}
                            refreshDistance(true);
                        }
                    });
                });
            }
        }
        if (sel.value && sel.value !== 'all') update();
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', autoInit);
    } else {
        autoInit();
    }

    // Expose for late-mounted forms (e.g., dynamic modals)
    window.enhanceCategoryPicker = enhance;
})();
