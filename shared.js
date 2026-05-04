// shared.js — Bottom Tab Bar + Global Modal Backdrop Handler
(function() {
    var page = (window.location.pathname.split('/').pop() || 'index.html').toLowerCase();

    // Global helper for the bottom-bar "+" button.
    // The postTaskModal HTML only exists on index/posted/accepted/completed.
    // On other pages (browse, profile, wallet, etc.) we redirect to index.html#post
    // so the modal is opened on landing.
    window.__openPostTask = function() {
        try {
            var modal = document.getElementById('postTaskModal');
            if (modal && typeof openModal === 'function') {
                openModal('postTaskModal');
            } else {
                window.location.href = 'index.html#post';
            }
        } catch (_e) {
            window.location.href = 'index.html#post';
        }
        return false;
    };

    function initTabBar() {
        // Skip on pages that already have their own nav (task-in-progress, tracking, admin, etc.)
        if (['task-in-progress.html','tracking.html','admin.html','admin-dashboard.html'].indexOf(page) !== -1) return;

        var bar = document.createElement('nav');
        bar.className = 'bottom-tab-bar';
        bar.innerHTML =
            '<a href="index.html" class="' + (page === 'index.html' || page === '' ? 'active' : '') + '"><i class="fas fa-home"></i><span>Home</span></a>' +
            '<a href="browse.html" class="' + (page === 'browse.html' ? 'active' : '') + '"><i class="fas fa-search"></i><span>Browse</span></a>' +
            '<a href="#" class="tab-post-btn" onclick="return window.__openPostTask();" aria-label="Post a task"><i class="fas fa-plus"></i><span>Post</span></a>' +
            '<a href="posted.html" class="' + (['posted.html','accepted.html','completed.html'].indexOf(page) !== -1 ? 'active' : '') + '"><i class="fas fa-list-check"></i><span>My Tasks</span></a>' +
            '<a href="profile.html" class="' + (['profile.html','wallet.html','referral.html','notifications.html'].indexOf(page) !== -1 ? 'active' : '') + '"><i class="fas fa-user"></i><span>Profile</span></a>';
        document.body.appendChild(bar);
        document.body.classList.add('has-tab-bar');
    }

    // Global modal backdrop click handler (works for dynamically added modals too)
    function initModalBackdrop() {
        document.addEventListener('click', function(e) {
            if (e.target.classList && e.target.classList.contains('modal') && e.target.classList.contains('active')) {
                e.target.classList.remove('active');
                document.body.style.overflow = '';
                if (typeof clearRoute === 'function') clearRoute();
            }
        });
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function() {
            initTabBar();
            initModalBackdrop();
            maybeAutoOpenPost();
        });
    } else {
        initTabBar();
        initModalBackdrop();
        maybeAutoOpenPost();
    }

    // If we arrived at index.html#post, open the Post Task modal automatically.
    function maybeAutoOpenPost() {
        if (window.location.hash !== '#post') return;
        var tries = 0;
        var iv = setInterval(function() {
            tries++;
            var modal = document.getElementById('postTaskModal');
            if (modal && typeof openModal === 'function') {
                openModal('postTaskModal');
                // Clean the hash so refresh doesn't re-open
                try { history.replaceState(null, '', window.location.pathname + window.location.search); } catch(_){}
                clearInterval(iv);
            } else if (tries > 20) {
                clearInterval(iv);
            }
        }, 150);
    }
})();
