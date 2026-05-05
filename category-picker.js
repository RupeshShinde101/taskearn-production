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
            'Preferred vehicle type (car / auto / bike)',
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

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', autoInit);
    } else {
        autoInit();
    }

    // Expose for late-mounted forms (e.g., dynamic modals)
    window.enhanceCategoryPicker = enhance;
})();
