// ========================================
// Workmate4u Multi-language Support (i18n)
// ========================================

const TRANSLATIONS = {
    en: {
        // Navigation
        home: 'Home',
        postTask: 'Post Task',
        findTasks: 'Find Tasks',
        wallet: 'Wallet',
        notifications: 'Notifications',
        profile: 'Profile',
        login: 'Login',
        signUp: 'Sign Up',
        logout: 'Logout',

        // Auth
        welcomeBack: 'Welcome Back',
        createAccount: 'Create Account',
        emailAddress: 'Email Address',
        password: 'Password',
        forgotPassword: 'Forgot Password?',
        rememberMe: 'Remember me',
        dontHaveAccount: "Don't have an account?",
        alreadyHaveAccount: 'Already have an account?',
        firstName: 'First Name',
        lastName: 'Last Name',
        phoneNumber: 'Phone Number',
        dateOfBirth: 'Date of Birth',
        ageRequirement: 'You must be 16 or older to use Workmate4u',
        createStrongPassword: 'Create a strong password',
        agreeTerms: 'I agree to the',
        termsOfService: 'Terms of Service',
        privacyPolicy: 'Privacy Policy',
        orContinueWith: 'or continue with',

        // Tasks
        searchTasks: 'Search tasks...',
        allCategories: 'All Categories',
        distance: 'Distance',
        budgetRange: 'Budget Range',
        applyFilters: 'Apply Filters',
        clearAll: 'Clear All',
        noTasksFound: 'No tasks found. Try adjusting your filters.',
        taskBudget: 'Task Budget',
        serviceCharge: 'Service Charge',
        youPay: 'You Pay',
        workerEarns: 'Worker Earns',
        postATask: 'Post a Task',
        findTasksToDo: 'Find Tasks to Do',
        expires: 'Expires',
        postedBy: 'Posted by',

        // Wallet
        addMoney: 'Add Money',
        withdraw: 'Withdraw',
        transactions: 'Transactions',
        balance: 'Balance',

        // Profile
        editProfile: 'Edit Profile',
        settings: 'Settings',
        darkMode: 'Dark Mode',
        language: 'Language',
        reportUser: 'Report User',
        blockUser: 'Block User',
        unblockUser: 'Unblock User',
        blockedUsers: 'Blocked Users',

        // KYC
        verifyIdentity: 'Verify Identity',
        kycPending: 'Verification Pending',
        kycVerified: 'Verified ✅',
        kycRejected: 'Verification Rejected',
        submitKyc: 'Submit for Verification',
        documentType: 'Document Type',
        documentNumber: 'Document Number',

        // Report
        reportReason: 'Reason for Report',
        harassment: 'Harassment',
        fraud: 'Fraud / Scam',
        spam: 'Spam',
        inappropriate: 'Inappropriate Content',
        fakeProfile: 'Fake Profile',
        noShow: 'No Show',
        other: 'Other',
        additionalDetails: 'Additional Details',
        submitReport: 'Submit Report',

        // Common
        save: 'Save',
        cancel: 'Cancel',
        confirm: 'Confirm',
        delete: 'Delete',
        loading: 'Loading...',
        success: 'Success',
        error: 'Error',
        close: 'Close',
        viewAll: 'View All',
        and: 'and'
    },

    hi: {
        // Navigation
        home: 'होम',
        postTask: 'टास्क पोस्ट करें',
        findTasks: 'टास्क खोजें',
        wallet: 'वॉलेट',
        notifications: 'सूचनाएं',
        profile: 'प्रोफ़ाइल',
        login: 'लॉगिन',
        signUp: 'साइन अप',
        logout: 'लॉगआउट',

        // Auth
        welcomeBack: 'वापसी पर स्वागत है',
        createAccount: 'अकाउंट बनाएं',
        emailAddress: 'ईमेल पता',
        password: 'पासवर्ड',
        forgotPassword: 'पासवर्ड भूल गए?',
        rememberMe: 'मुझे याद रखें',
        dontHaveAccount: 'अकाउंट नहीं है?',
        alreadyHaveAccount: 'पहले से अकाउंट है?',
        firstName: 'पहला नाम',
        lastName: 'अंतिम नाम',
        phoneNumber: 'फोन नंबर',
        dateOfBirth: 'जन्म तिथि',
        ageRequirement: 'Workmate4u इस्तेमाल करने के लिए आपकी उम्र 16 या अधिक होनी चाहिए',
        createStrongPassword: 'एक मजबूत पासवर्ड बनाएं',
        agreeTerms: 'मैं सहमत हूं',
        termsOfService: 'सेवा की शर्तें',
        privacyPolicy: 'गोपनीयता नीति',
        orContinueWith: 'या इसके साथ जारी रखें',

        // Tasks
        searchTasks: 'टास्क खोजें...',
        allCategories: 'सभी श्रेणियां',
        distance: 'दूरी',
        budgetRange: 'बजट रेंज',
        applyFilters: 'फ़िल्टर लागू करें',
        clearAll: 'सभी हटाएं',
        noTasksFound: 'कोई टास्क नहीं मिला। अपने फ़िल्टर बदलकर देखें।',
        taskBudget: 'टास्क बजट',
        serviceCharge: 'सर्विस चार्ज',
        youPay: 'आप भुगतान करें',
        workerEarns: 'वर्कर कमाएगा',
        postATask: 'टास्क पोस्ट करें',
        findTasksToDo: 'करने के लिए टास्क खोजें',
        expires: 'समय सीमा',
        postedBy: 'पोस्ट किया',

        // Wallet
        addMoney: 'पैसे जोड़ें',
        withdraw: 'निकासी',
        transactions: 'लेनदेन',
        balance: 'बैलेंस',

        // Profile
        editProfile: 'प्रोफ़ाइल संपादित करें',
        settings: 'सेटिंग्स',
        darkMode: 'डार्क मोड',
        language: 'भाषा',
        reportUser: 'यूजर की रिपोर्ट करें',
        blockUser: 'यूजर को ब्लॉक करें',
        unblockUser: 'अनब्लॉक करें',
        blockedUsers: 'ब्लॉक किए गए यूजर',

        // KYC
        verifyIdentity: 'पहचान सत्यापित करें',
        kycPending: 'सत्यापन लंबित',
        kycVerified: 'सत्यापित ✅',
        kycRejected: 'सत्यापन अस्वीकृत',
        submitKyc: 'सत्यापन के लिए जमा करें',
        documentType: 'दस्तावेज़ का प्रकार',
        documentNumber: 'दस्तावेज़ नंबर',

        // Report
        reportReason: 'रिपोर्ट का कारण',
        harassment: 'उत्पीड़न',
        fraud: 'धोखाधड़ी',
        spam: 'स्पैम',
        inappropriate: 'अनुचित सामग्री',
        fakeProfile: 'फर्जी प्रोफ़ाइल',
        noShow: 'उपस्थित नहीं हुआ',
        other: 'अन्य',
        additionalDetails: 'अतिरिक्त विवरण',
        submitReport: 'रिपोर्ट जमा करें',

        // Common
        save: 'सेव करें',
        cancel: 'रद्द करें',
        confirm: 'पुष्टि करें',
        delete: 'हटाएं',
        loading: 'लोड हो रहा है...',
        success: 'सफल',
        error: 'त्रुटि',
        close: 'बंद करें',
        viewAll: 'सभी देखें',
        and: 'और'
    },

    mr: {
        // Navigation
        home: 'होम',
        postTask: 'टास्क पोस्ट करा',
        findTasks: 'टास्क शोधा',
        wallet: 'वॉलेट',
        notifications: 'सूचना',
        profile: 'प्रोफाइल',
        login: 'लॉगिन',
        signUp: 'साइन अप',
        logout: 'लॉगआउट',

        // Auth
        welcomeBack: 'पुन्हा स्वागत आहे',
        createAccount: 'अकाउंट तयार करा',
        emailAddress: 'ईमेल पत्ता',
        password: 'पासवर्ड',
        forgotPassword: 'पासवर्ड विसरलात?',
        rememberMe: 'मला लक्षात ठेवा',
        dontHaveAccount: 'अकाउंट नाही?',
        alreadyHaveAccount: 'आधीच अकाउंट आहे?',
        firstName: 'पहिले नाव',
        lastName: 'आडनाव',
        phoneNumber: 'फोन नंबर',
        dateOfBirth: 'जन्मतारीख',
        ageRequirement: 'Workmate4u वापरण्यासाठी तुमचे वय 16 किंवा त्यापेक्षा जास्त असावे',
        createStrongPassword: 'एक मजबूत पासवर्ड तयार करा',
        agreeTerms: 'मी सहमत आहे',
        termsOfService: 'सेवा अटी',
        privacyPolicy: 'गोपनीयता धोरण',
        orContinueWith: 'किंवा यासह सुरू ठेवा',

        // Tasks
        searchTasks: 'टास्क शोधा...',
        allCategories: 'सर्व श्रेणी',
        distance: 'अंतर',
        budgetRange: 'बजेट श्रेणी',
        applyFilters: 'फिल्टर लागू करा',
        clearAll: 'सर्व काढा',
        noTasksFound: 'कोणतेही टास्क सापडले नाहीत.',
        taskBudget: 'टास्क बजेट',
        serviceCharge: 'सर्व्हिस चार्ज',
        youPay: 'तुम्ही भरा',
        workerEarns: 'वर्कर कमवेल',
        postATask: 'टास्क पोस्ट करा',
        findTasksToDo: 'करायला टास्क शोधा',
        expires: 'मुदत',
        postedBy: 'पोस्ट केले',

        // Wallet
        addMoney: 'पैसे जोडा',
        withdraw: 'पैसे काढा',
        transactions: 'व्यवहार',
        balance: 'शिल्लक',

        // Profile
        editProfile: 'प्रोफाइल संपादित करा',
        settings: 'सेटिंग्ज',
        darkMode: 'डार्क मोड',
        language: 'भाषा',
        reportUser: 'युजरची तक्रार करा',
        blockUser: 'युजर ब्लॉक करा',
        unblockUser: 'अनब्लॉक करा',
        blockedUsers: 'ब्लॉक केलेले युजर',

        // KYC
        verifyIdentity: 'ओळख सत्यापित करा',
        kycPending: 'सत्यापन प्रलंबित',
        kycVerified: 'सत्यापित ✅',
        kycRejected: 'सत्यापन नाकारले',
        submitKyc: 'सत्यापनासाठी सबमिट करा',
        documentType: 'कागदपत्र प्रकार',
        documentNumber: 'कागदपत्र क्रमांक',

        // Report
        reportReason: 'तक्रारीचे कारण',
        harassment: 'छळवणूक',
        fraud: 'फसवणूक',
        spam: 'स्पॅम',
        inappropriate: 'अयोग्य सामग्री',
        fakeProfile: 'बनावट प्रोफाइल',
        noShow: 'हजर नव्हता',
        other: 'इतर',
        additionalDetails: 'अतिरिक्त तपशील',
        submitReport: 'तक्रार सबमिट करा',

        // Common
        save: 'सेव करा',
        cancel: 'रद्द करा',
        confirm: 'पुष्टी करा',
        delete: 'हटवा',
        loading: 'लोड होत आहे...',
        success: 'यशस्वी',
        error: 'त्रुटी',
        close: 'बंद करा',
        viewAll: 'सर्व पहा',
        and: 'आणि'
    }
};

// Current language
let currentLanguage = localStorage.getItem('w4u_language') || 'en';

/**
 * Get translated string by key
 * Falls back to English if key not found in target language
 */
function t(key) {
    const lang = TRANSLATIONS[currentLanguage] || TRANSLATIONS.en;
    return lang[key] || TRANSLATIONS.en[key] || key;
}

/**
 * Set language and persist choice
 */
async function setLanguage(lang) {
    if (!TRANSLATIONS[lang]) {
        console.warn('Unsupported language:', lang);
        return;
    }
    currentLanguage = lang;
    localStorage.setItem('w4u_language', lang);

    // Save to server if logged in
    if (typeof LanguageAPI !== 'undefined' && typeof AuthAPI !== 'undefined' && AuthAPI.isLoggedIn()) {
        try {
            await LanguageAPI.setLanguage(lang);
        } catch (e) {
            console.warn('Failed to save language preference:', e);
        }
    }

    // Update visible text on page
    applyTranslations();
}

/**
 * Apply translations to all elements with data-i18n attribute
 */
function applyTranslations() {
    document.querySelectorAll('[data-i18n]').forEach(el => {
        const key = el.getAttribute('data-i18n');
        const text = t(key);
        if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') {
            el.placeholder = text;
        } else {
            el.textContent = text;
        }
    });

    // Update data-i18n-placeholder
    document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
        el.placeholder = t(el.getAttribute('data-i18n-placeholder'));
    });
}

/**
 * Get list of available languages
 */
function getAvailableLanguages() {
    return [
        { code: 'en', name: 'English', nativeName: 'English' },
        { code: 'hi', name: 'Hindi', nativeName: 'हिन्दी' },
        { code: 'mr', name: 'Marathi', nativeName: 'मराठी' }
    ];
}

// Export
window.t = t;
window.setLanguage = setLanguage;
window.applyTranslations = applyTranslations;
window.getAvailableLanguages = getAvailableLanguages;
window.currentLanguage = currentLanguage;
