// shared.js — Bottom Tab Bar + Global Modal Backdrop Handler
(function() {
    var page = (window.location.pathname.split('/').pop() || 'index.html').toLowerCase();

    function initTabBar() {
        // Skip on pages that already have their own nav (task-in-progress, tracking, admin, etc.)
        if (['task-in-progress.html','tracking.html','admin.html','admin-dashboard.html'].indexOf(page) !== -1) return;

        var bar = document.createElement('nav');
        bar.className = 'bottom-tab-bar';
        // On browse.html the section is dedicated to finding/accepting available tasks only,
        // so the central "Post" action is omitted there.
        var hidePost = (page === 'browse.html');
        var postTab = hidePost ? '' :
            '<a href="#" class="tab-post-btn" onclick="if(typeof openModal===\'function\'){openModal(\'postTaskModal\');}else{window.location.href=\'index.html#post\';}return false;" aria-label="Post a task"><i class="fas fa-plus"></i><span>Post</span></a>';
        bar.innerHTML =
            '<a href="index.html" class="' + (page === 'index.html' || page === '' ? 'active' : '') + '"><i class="fas fa-home"></i><span>Home</span></a>' +
            '<a href="browse.html" class="' + (page === 'browse.html' ? 'active' : '') + '"><i class="fas fa-search"></i><span>Browse</span></a>' +
            postTab +
            '<a href="posted.html" class="' + (['posted.html','accepted.html','completed.html'].indexOf(page) !== -1 ? 'active' : '') + '"><i class="fas fa-list-check"></i><span>My Tasks</span></a>' +
            '<a href="profile.html" class="' + (['profile.html','wallet.html','referral.html','notifications.html'].indexOf(page) !== -1 ? 'active' : '') + '"><i class="fas fa-user"></i><span>Profile</span></a>';
        if (hidePost) bar.classList.add('no-post');
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
        });
    } else {
        initTabBar();
        initModalBackdrop();
    }
})();
