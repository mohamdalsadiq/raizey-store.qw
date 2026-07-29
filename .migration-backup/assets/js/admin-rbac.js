// =========================================================
// RAIZ3Y STORE — Admin RBAC Helpers (Phase 1)
// =========================================================
(function attachAdminRbac(global) {
  if (!global.supabaseClient) {
    throw new Error('supabaseClient is required before loading admin-rbac.js');
  }

  function normaliseContext(payload) {
    const permissions = payload?.permissions || {};
    return {
      userId: payload?.user_id || null,
      legacyAdmin: Boolean(payload?.legacy_admin),
      isAdmin: Boolean(payload?.is_admin),
      isSuperAdmin: Boolean(payload?.is_super_admin),
      permissions: {
        is_super_admin: Boolean(permissions.is_super_admin),
        can_manage_orders: Boolean(permissions.can_manage_orders),
        can_manage_wallets: Boolean(permissions.can_manage_wallets),
        can_manage_products: Boolean(permissions.can_manage_products),
        can_manage_settings: Boolean(permissions.can_manage_settings),
        can_manage_maintenance: Boolean(permissions.can_manage_maintenance),
        can_manage_admins: Boolean(permissions.can_manage_admins),
        can_manage_coupons: Boolean(permissions.can_manage_coupons),
        can_manage_gift_cards: Boolean(permissions.can_manage_gift_cards),
        can_view_audit_logs: Boolean(permissions.can_view_audit_logs)
      }
    };
  }

  function mapPermission(permissionKey) {
    const map = {
      manage_orders: 'can_manage_orders',
      manage_wallets: 'can_manage_wallets',
      manage_products: 'can_manage_products',
      manage_settings: 'can_manage_settings',
      manage_maintenance: 'can_manage_maintenance',
      manage_admins: 'can_manage_admins',
      manage_coupons: 'can_manage_coupons',
      manage_gift_cards: 'can_manage_gift_cards',
      view_audit_logs: 'can_view_audit_logs'
    };
    return map[permissionKey] || null;
  }

  function formatRpcError(error) {
    const raw = String(error?.message || error || '').trim();

    if (!raw) return 'تعذر تنفيذ العملية حالياً.';
    if (raw.includes('AUTH_REQUIRED')) return 'يجب تسجيل الدخول أولاً.';
    if (raw.includes('BOOTSTRAP_REQUIRES_LEGACY_ADMIN_ROLE')) {
      return 'يجب أن يكون الحساب الحالي مسجلاً كأدمن في profiles.role قبل تنفيذ التهيئة الأولى.';
    }
    if (raw.includes('SUPER_ADMIN_ALREADY_EXISTS')) {
      return 'تم تعيين Super Admin بالفعل. لا يمكن تنفيذ التهيئة الأولى من هذا الحساب.';
    }
    if (raw.includes('MISSING_PERMISSION')) return 'الحساب الحالي لا يملك الصلاحية المطلوبة.';
    if (raw.includes('LAST_SUPER_ADMIN_PROTECTION')) {
      return 'لا يمكن إزالة آخر Super Admin من النظام.';
    }

    return raw;
  }

  const adminRbac = {
    async getSession() {
      const { data, error } = await global.supabaseClient.auth.getSession();
      if (error) throw error;
      return data?.session || null;
    },

    async getMyContext() {
      const { data, error } = await global.supabaseClient.rpc('get_my_admin_context');
      if (error) throw error;
      return normaliseContext(data || {});
    },

    can(permissionKey, context) {
      if (!context) return false;
      if (context.isSuperAdmin) return true;

      const fieldName = mapPermission(permissionKey);
      if (!fieldName) return false;
      return Boolean(context.permissions?.[fieldName]);
    },

    async bootstrapCurrentUser() {
      const { data, error } = await global.supabaseClient.rpc('bootstrap_super_admin');
      if (error) throw error;
      return data;
    },

    async appendAuditLog(action, targetTable, targetId, details) {
      const { data, error } = await global.supabaseClient.rpc('append_admin_audit_log', {
        p_action: action,
        p_target_table: targetTable || null,
        p_target_id: targetId || null,
        p_details: details || {}
      });
      if (error) throw error;
      return data;
    },

    formatRpcError
  };

  global.adminRbac = adminRbac;
})(window);
