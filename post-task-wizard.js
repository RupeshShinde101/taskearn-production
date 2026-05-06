/* ============================================
 * post-task-wizard.js
 * 4-step wizard controller for #postTaskModal
 *
 *   Step 1: Title + Category + Description
 *   Step 2: When (date)
 *   Step 3: Location + Budget (pickup, drop auto-injected for transport/delivery/moving,
 *           plus vehicle chips + fair-price hint + custom budget + nudges)
 *   Step 4: Review + service charge breakdown + Post
 *
 * Per-category UX:
 *   - Step 3 heading adapts for transport / delivery / moving / others.
 *   - Step 1 description placeholder is set by category-picker.js TEMPLATES.
 *   - Vehicle picker / fair-price hint mounts into #wmPriceHintSlot on step 3.
 * ============================================ */
(function () {
    'use strict';

    const TOTAL_STEPS = 4;

    // Categories that are distance-priced (and thus need pickup + drop)
    const DISTANCE_CATS = new Set(['transport', 'delivery', 'moving']);

    let currentStep = 1;

    function $(id) { return document.getElementById(id); }
    function modalOpen() {
        const m = $('postTaskModal');
        return m && (m.classList.contains('active') || m.classList.contains('show') || getComputedStyle(m).display !== 'none');
    }

    function getStepEls() {
        return Array.from(document.querySelectorAll('#postTaskModal .wm-step'));
    }
    function getTabEls() {
        return Array.from(document.querySelectorAll('#postTaskModal .wm-step-tab'));
    }

    function applyCategoryLabels() {
        const cat = ($('modalTaskCategory') || {}).value || '';
        const isDistance = DISTANCE_CATS.has(cat);
        const isTransport = cat === 'transport';

        // Step 3 (Location & Budget) labels
        const step3Label = $('wmStep3Label');
        const step3Heading = $('wmStep3Heading');
        const step3Sub = $('wmStep3Sub');
        if (step3Label) step3Label.textContent = isDistance ? 'Pickup, Drop & Budget' : 'Location & Budget';
        if (step3Heading) {
            step3Heading.innerHTML = isDistance
                ? '<i class="fas fa-route"></i> Pickup, drop &amp; budget'
                : '<i class="fas fa-map-marker-alt"></i> Location &amp; budget';
        }
        if (step3Sub) {
            step3Sub.textContent = isTransport
                ? 'Set the pickup spot and drop, choose a vehicle, then confirm the fair price.'
                : isDistance
                    ? 'Set pickup and drop to compute fair distance pricing, then confirm the budget.'
                    : 'Enter the address, then choose a fair budget.';
        }
    }

    function validateStep(step) {
        clearStepError();
        if (step === 1) {
            const title = ($('modalTaskTitle').value || '').trim();
            const cat = $('modalTaskCategory').value;
            const desc = ($('modalTaskDescription').value || '').trim();
            if (!title) return 'Please enter a task title.';
            if (title.length < 4) return 'Title is too short — describe what you need.';
            if (!cat) return 'Please pick a category.';
            if (!desc || desc.length < 10) return 'Please add a short description (at least 10 characters).';
        } else if (step === 2) {
            const dt = $('modalTaskDate').value;
            if (!dt) return 'Please pick when you need this done.';
            const when = new Date(dt).getTime();
            if (isNaN(when)) return 'Please pick a valid date and time.';
            if (when < Date.now() - 5 * 60 * 1000) return 'Please pick a future date and time.';
        } else if (step === 3) {
            const loc = ($('modalTaskLocation').value || '').trim();
            if (!loc) return 'Please enter the task location (or use My Location / Pick on Map).';
            const cat = $('modalTaskCategory').value;
            if (DISTANCE_CATS.has(cat)) {
                const dropEl = $('modalTaskLocation_drop');
                const dropVal = dropEl ? (dropEl.value || '').trim() : '';
                if (!dropVal) return 'Please set the drop location.';
            }
            const v = parseFloat(($('customBudget') || {}).value);
            if (!v || v < 100) return 'Minimum task budget is ₹100.';
        }
        return null;
    }

    function showStepError(msg) {
        clearStepError();
        const active = document.querySelector('#postTaskModal .wm-step.active');
        if (!active) return;
        const err = document.createElement('div');
        err.className = 'wm-step-error';
        err.id = 'wmStepError';
        err.textContent = msg;
        active.appendChild(err);
        if (window.showToast) window.showToast('⚠️ ' + msg);
    }
    function clearStepError() {
        const e = $('wmStepError');
        if (e) e.remove();
    }

    function buildReviewSummary() {
        const cat = $('modalTaskCategory').value || '';
        const catLabel = ($('modalTaskCategory').selectedOptions[0] || {}).text || cat;
        const title = ($('modalTaskTitle').value || '').trim();
        const date = $('modalTaskDate').value;
        const dateStr = date ? new Date(date).toLocaleString('en-IN', { dateStyle: 'medium', timeStyle: 'short' }) : '—';
        const pickup = ($('modalTaskLocation').value || '').trim();
        const dropEl = $('modalTaskLocation_drop');
        const drop = dropEl ? (dropEl.value || '').trim() : '';
        const budget = parseFloat(($('customBudget') || {}).value) || 0;
        const veh = window.__wmSelectedVehicle;
        const VEHICLE_LABEL = { bike: '🏍️ Bike', auto: '🛺 Auto', mini: '🚗 Mini Car', sedan: '🚙 Sedan' };
        const distance = (typeof window.__wmLastDistance === 'number') ? window.__wmLastDistance.toFixed(1) + ' km' : null;

        const rows = [];
        rows.push(['Task', title || '—']);
        rows.push(['Category', catLabel]);
        rows.push(['When', dateStr]);
        if (DISTANCE_CATS.has(cat)) {
            rows.push(['Pickup', pickup || '—']);
            rows.push(['Drop', drop || '—']);
            if (distance) rows.push(['Distance', distance]);
            if (veh && VEHICLE_LABEL[veh]) rows.push(['Vehicle', VEHICLE_LABEL[veh]]);
        } else {
            rows.push(['Location', pickup || '—']);
        }
        rows.push(['Budget', '₹' + budget]);

        const html = rows.map(([k, v]) =>
            '<div class="wm-review-row"><span class="wm-review-label">' + k +
            '</span><span class="wm-review-value">' + escapeHtml(String(v)) + '</span></div>'
        ).join('');
        const container = $('wmReviewSummary');
        if (container) container.innerHTML = html;
    }

    function escapeHtml(s) {
        return s.replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    }

    function goToStep(n, opts) {
        opts = opts || {};
        n = Math.max(1, Math.min(TOTAL_STEPS, n));

        // Forward validation
        if (!opts.skipValidate && n > currentStep) {
            for (let s = currentStep; s < n; s++) {
                const err = validateStep(s);
                if (err) { showStepError(err); return false; }
            }
        }

        currentStep = n;
        clearStepError();

        // Show/hide step panels
        getStepEls().forEach(el => {
            const stepNum = parseInt(el.dataset.step, 10);
            const isActive = stepNum === n;
            el.classList.toggle('active', isActive);
            if (isActive) el.removeAttribute('hidden');
            else el.setAttribute('hidden', '');
        });

        // Update tab buttons
        getTabEls().forEach(btn => {
            const stepNum = parseInt(btn.dataset.step, 10);
            btn.classList.toggle('active', stepNum === n);
            btn.classList.toggle('completed', stepNum < n);
            btn.setAttribute('aria-selected', stepNum === n ? 'true' : 'false');
        });

        // Progress bar
        const bar = $('wmStepProgressBar');
        if (bar) bar.style.width = (n / TOTAL_STEPS * 100) + '%';

        // Buttons
        const prev = $('wmStepPrev');
        const next = $('wmStepNext');
        const submit = $('wmStepSubmit');
        if (prev) prev.style.display = n > 1 ? '' : 'none';
        if (next) next.style.display = n < TOTAL_STEPS ? '' : 'none';
        if (submit) submit.style.display = n === TOTAL_STEPS ? '' : 'none';

        // On entering step 5, refresh review summary + recompute totals
        if (n === TOTAL_STEPS) {
            buildReviewSummary();
            try { if (window.updateTotalBudgetDisplay) window.updateTotalBudgetDisplay(); } catch (e) { /* noop */ }
        }

        // Scroll modal content to top
        const mc = document.querySelector('#postTaskModal .modal-content');
        if (mc) mc.scrollTop = 0;

        return true;
    }

    function reset() {
        currentStep = 1;
        clearStepError();
        applyCategoryLabels();
        goToStep(1, { skipValidate: true });
    }

    function bindQuickWhenChips() {
        document.querySelectorAll('#postTaskModal .wm-when-chip').forEach(btn => {
            if (btn.dataset.wmWhenWired) return;
            btn.dataset.wmWhenWired = '1';
            btn.addEventListener('click', () => {
                const code = btn.dataset.when;
                const now = new Date();
                let target = new Date(now);
                if (code === 'now') {
                    target = new Date(now.getTime() + 30 * 60 * 1000);
                } else if (code === '2h') {
                    target = new Date(now.getTime() + 2 * 60 * 60 * 1000);
                } else if (code === 'today-evening') {
                    target.setHours(18, 0, 0, 0);
                    if (target.getTime() < now.getTime() + 30 * 60 * 1000) {
                        target = new Date(now.getTime() + 90 * 60 * 1000);
                    }
                } else if (code === 'tomorrow-morning') {
                    target.setDate(target.getDate() + 1);
                    target.setHours(9, 0, 0, 0);
                }
                const dt = $('modalTaskDate');
                if (dt) {
                    const pad = n => String(n).padStart(2, '0');
                    const v = target.getFullYear() + '-' + pad(target.getMonth() + 1) + '-' + pad(target.getDate())
                        + 'T' + pad(target.getHours()) + ':' + pad(target.getMinutes());
                    dt.value = v;
                }
                document.querySelectorAll('#postTaskModal .wm-when-chip').forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
            });
        });
    }

    function bindNavButtons() {
        const prev = $('wmStepPrev');
        const next = $('wmStepNext');
        if (next && !next.dataset.wmWired) {
            next.dataset.wmWired = '1';
            next.addEventListener('click', () => goToStep(currentStep + 1));
        }
        if (prev && !prev.dataset.wmWired) {
            prev.dataset.wmWired = '1';
            prev.addEventListener('click', () => goToStep(currentStep - 1, { skipValidate: true }));
        }

        // Tab clicks: backward freely, forward only with validation
        getTabEls().forEach(btn => {
            if (btn.dataset.wmWired) return;
            btn.dataset.wmWired = '1';
            btn.addEventListener('click', () => {
                const target = parseInt(btn.dataset.step, 10);
                if (!target) return;
                if (target <= currentStep) {
                    goToStep(target, { skipValidate: true });
                } else {
                    goToStep(target);
                }
            });
        });
    }

    function bindCategoryChange() {
        const sel = $('modalTaskCategory');
        if (!sel || sel.dataset.wmWizardWired) return;
        sel.dataset.wmWizardWired = '1';
        sel.addEventListener('change', applyCategoryLabels);
    }

    // Watch for the postTaskModal becoming visible — reset to step 1.
    function observeOpen() {
        const m = $('postTaskModal');
        if (!m) return;
        let wasOpen = false;
        const check = () => {
            const open = modalOpen();
            if (open && !wasOpen) {
                wasOpen = true;
                bindNavButtons();
                bindQuickWhenChips();
                bindCategoryChange();
                reset();
            } else if (!open && wasOpen) {
                wasOpen = false;
            }
        };
        const obs = new MutationObserver(check);
        obs.observe(m, { attributes: true, attributeFilter: ['class', 'style'] });
        // Initial check (in case modal is already open)
        check();
    }

    // Auto-upgrade legacy long-scroll #postTaskModal on pages that haven't been
    // hand-converted to the wizard layout yet.  Detects the absence of any
    // .wm-step children and rewrites the modal-content innerHTML to match the
    // wizard markup used in index.html.
    function autoUpgradeLegacyModal() {
        const modal = $('postTaskModal');
        if (!modal) return;
        const mc = modal.querySelector('.modal-content');
        if (!mc) return;
        if (mc.querySelector('.wm-step')) return; // already wizard
        if (!mc.querySelector('#modalTaskForm')) return; // not a post-task modal

        mc.classList.add('modal-large', 'wm-wizard-modal');
        mc.innerHTML = WIZARD_MARKUP;
    }

    const WIZARD_MARKUP = `
            <button class="modal-close" onclick="closeModal('postTaskModal')" aria-label="Close">
                <i class="fas fa-times"></i>
            </button>
            <h2><i class="fas fa-plus-circle"></i> Post a New Task</h2>
            <div class="wm-step-nav" id="wmStepNav" role="tablist" aria-label="Post task steps">
                <button type="button" class="wm-step-tab active" data-step="1" role="tab" aria-selected="true"><span class="wm-step-num">1</span><span class="wm-step-label">Basics</span></button>
                <button type="button" class="wm-step-tab" data-step="2" role="tab" aria-selected="false"><span class="wm-step-num">2</span><span class="wm-step-label">When</span></button>
                <button type="button" class="wm-step-tab" data-step="3" role="tab" aria-selected="false"><span class="wm-step-num">3</span><span class="wm-step-label" id="wmStep3Label">Location &amp; Budget</span></button>
                <button type="button" class="wm-step-tab" data-step="4" role="tab" aria-selected="false"><span class="wm-step-num">4</span><span class="wm-step-label">Review</span></button>
            </div>
            <div class="wm-step-progress" aria-hidden="true"><div class="wm-step-progress-bar" id="wmStepProgressBar" style="width:25%"></div></div>
            <form id="modalTaskForm" onsubmit="handleTaskSubmit(event)" novalidate>
                <section class="wm-step active" data-step="1" role="tabpanel">
                    <div class="wm-step-head"><h3><i class="fas fa-pen"></i> What do you need help with?</h3><p class="wm-step-sub">Give your task a clear title, pick a category, and describe what you need.</p></div>
                    <div class="form-group"><label for="modalTaskTitle">Task Title</label><input type="text" id="modalTaskTitle" placeholder="What do you need help with?" required></div>
                    <div class="form-group"><label for="modalTaskCategory">Category</label><select id="modalTaskCategory" required>
                        <option value="">Select category</option>
                        <option value="household">Household Chores</option><option value="delivery">Delivery Services</option><option value="tutoring">Online Tutoring</option><option value="transport">Pick & Drop</option><option value="vehicle">Vehicle Services</option><option value="repair">Repairs & Mechanical</option><option value="photography">Photography</option><option value="freelance">Freelance Services</option><option value="waste">Waste Collection</option><option value="cleaning">Cleaning Services</option><option value="cooking">Cooking & Chef</option><option value="petcare">Pet Care</option><option value="gardening">Gardening & Lawn</option><option value="shopping">Shopping & Errands</option><option value="eventhelp">Event Help</option><option value="moving">Moving & Packing</option><option value="techsupport">Tech Support</option><option value="beauty">Beauty & Wellness</option><option value="laundry">Laundry & Ironing</option><option value="catering">Catering Services</option><option value="babysitting">Babysitting</option><option value="eldercare">Elder Care</option><option value="fitness">Fitness Training</option><option value="painting">Painting & Decor</option><option value="electrician">Electrician</option><option value="plumbing">Plumbing</option><option value="carpentry">Carpentry</option><option value="tailoring">Tailoring & Alterations</option><option value="other">Other</option>
                    </select></div>
                    <div class="form-group"><label for="modalTaskDescription">Description</label><textarea id="modalTaskDescription" rows="5" placeholder="Provide details about the task, any special requirements, etc." required></textarea></div>
                </section>
                <section class="wm-step" data-step="2" role="tabpanel" hidden>
                    <div class="wm-step-head"><h3><i class="fas fa-calendar-alt"></i> When do you need this done?</h3><p class="wm-step-sub">Pick a date and time. Tasks are visible to nearby taskers for 12 hours after posting.</p></div>
                    <div class="form-group"><label for="modalTaskDate">Required by</label><input type="datetime-local" id="modalTaskDate" required></div>
                    <div class="wm-quick-when">
                        <button type="button" class="wm-when-chip" data-when="now">ASAP</button>
                        <button type="button" class="wm-when-chip" data-when="2h">In 2 hours</button>
                        <button type="button" class="wm-when-chip" data-when="today-evening">Today evening</button>
                        <button type="button" class="wm-when-chip" data-when="tomorrow-morning">Tomorrow 9am</button>
                    </div>
                </section>
                <section class="wm-step" data-step="3" role="tabpanel" hidden>
                    <div class="wm-step-head"><h3 id="wmStep3Heading"><i class="fas fa-map-marker-alt"></i> Location &amp; Budget</h3><p class="wm-step-sub" id="wmStep3Sub">Set the address, then choose a fair budget.</p></div>
                    <div class="form-group"><label for="modalTaskLocation">Task Location</label><div class="location-input-wrapper"><input type="text" id="modalTaskLocation" placeholder="Enter the address where task needs to be done" required><button type="button" class="location-btn" onclick="getModalLocation()"><i class="fas fa-map-marker-alt"></i> Use My Location</button></div></div>
                    <div id="wmPriceHintSlot"></div>
                    <div class="form-group"><label>Task Budget <span style="font-weight:400;color:#64748b;font-size:0.85em">(Min ₹100)</span></label><div class="budget-selector budget-selector-compact"><input type="number" id="customBudget" placeholder="Enter your budget (₹)" min="100" style="flex:1;font-size:1.05rem;padding:11px 14px;"></div></div>
                    <div class="form-group"><label><i class="fas fa-plus-circle"></i> Nudge Budget (Optional)</label><div class="bonus-section"><p class="bonus-hint">Small bumps to attract taskers faster. Tap to add to your budget.</p><div class="bonus-options"><button type="button" class="bonus-btn" onclick="nudgeBudget(10)">+₹10</button><button type="button" class="bonus-btn" onclick="nudgeBudget(20)">+₹20</button><button type="button" class="bonus-btn" onclick="nudgeBudget(50)">+₹50</button><button type="button" class="bonus-btn bonus-btn-minus" onclick="nudgeBudget(-10)">−₹10</button></div><div class="total-budget-display"><span>Task Budget:</span><strong id="totalBudgetDisplay">₹100</strong></div></div></div>
                </section>
                <section class="wm-step" data-step="4" role="tabpanel" hidden>
                    <div class="wm-step-head"><h3><i class="fas fa-receipt"></i> Review &amp; Post</h3><p class="wm-step-sub">Quick summary of what you're posting and the total amount you'll pay.</p></div>
                    <div class="wm-review-summary" id="wmReviewSummary"></div>
                    <div class="service-charge-box"><div class="charge-header"><i class="fas fa-receipt"></i><span>Service Charge</span></div><div class="charge-details"><div class="charge-row"><span>Task Budget:</span><span id="displayTaskBudget">₹100</span></div><div class="charge-row" style="color:#10b981;"><span>+ Service Charge (<span id="serviceChargeLevel">Medium</span>):</span><span id="serviceChargeAmount">₹50</span></div><div class="charge-row" style="font-size:12px;color:#666;"><span>Est. Time:</span><span id="serviceChargeTime">1-3 hours</span></div><div class="charge-row total"><span><strong>You Pay:</strong></span><span><strong id="totalPayable">₹150</strong></span></div><div class="charge-row" style="color:#10b981;font-size:13px;margin-top:5px;"><span>Worker Earns:</span><span><strong id="workerEarns">₹150</strong></span></div></div><p class="charge-note"><i class="fas fa-info-circle"></i> Service charge: Pick&Drop / Delivery ₹10–₹40 (by distance) | Medium ₹40–50 | Skilled ₹60–70 | Expert ₹70–80 | Professional ₹90–100</p></div>
                    <div class="task-info-box"><i class="fas fa-info-circle"></i><div><strong>Task Visibility</strong><p>Your task will be visible to nearby taskers for 12 hours. You can edit or delete the task anytime before it's accepted.</p></div></div>
                </section>
                <div class="wm-step-actions">
                    <button type="button" class="btn btn-secondary wm-step-prev" id="wmStepPrev" style="display:none;"><i class="fas fa-arrow-left"></i> Back</button>
                    <button type="button" class="btn btn-primary wm-step-next" id="wmStepNext">Next <i class="fas fa-arrow-right"></i></button>
                    <button type="submit" class="btn btn-primary btn-large wm-step-submit" id="wmStepSubmit" style="display:none;"><i class="fas fa-paper-plane"></i> Post Task Now</button>
                </div>
            </form>
    `;

    // Hijack the form's submit so users can't submit from earlier steps via Enter.
    function guardSubmit() {
        const form = $('modalTaskForm');
        if (!form || form.dataset.wmGuard) return;
        form.dataset.wmGuard = '1';
        form.addEventListener('submit', (e) => {
            if (currentStep !== TOTAL_STEPS) {
                e.preventDefault();
                e.stopImmediatePropagation();
                goToStep(currentStep + 1);
                return false;
            }
            // Final validation before submit
            for (let s = 1; s < TOTAL_STEPS; s++) {
                const err = validateStep(s);
                if (err) {
                    e.preventDefault();
                    e.stopImmediatePropagation();
                    goToStep(s, { skipValidate: true });
                    showStepError(err);
                    return false;
                }
            }
        }, true); // capture so we run before handleTaskSubmit
    }

    function init() {
        // If the modal exists but is the legacy single-form layout (no .wm-step),
        // rebuild it into the wizard layout so all pages get the same UX.
        autoUpgradeLegacyModal();
        bindNavButtons();
        bindQuickWhenChips();
        bindCategoryChange();
        guardSubmit();
        observeOpen();
        applyCategoryLabels();
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }

    // Expose a tiny API for debugging / external triggers
    window.WMPostTaskWizard = {
        goToStep,
        reset,
        validate: validateStep,
        get step() { return currentStep; },
    };
})();
