-- Keep manager base-role grants away from sensitive HR permissions while
-- allowing owners/admins and explicitly assigned custom roles to receive them.
create or replace function public.has_org_permission(target_org uuid, permission_key text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.org_members m
    where m.organization_id = target_org and m.user_id = (select auth.uid()) and m.status = 'active'
      and (
        m.role in ('owner', 'admin')
        or (m.role = 'manager' and permission_key not in (
          'organization.manage', 'finance.manage', 'members.manage',
          'hr.leave.manage', 'hr.attendance.manage', 'hr.payroll.manage',
          'hr.documents.manage'
        ))
        or exists (
          select 1 from public.role_assignments ra join public.roles r on r.id = ra.role_id
          where ra.organization_id = m.organization_id and ra.user_id = m.user_id
            and coalesce((r.permissions ->> permission_key)::boolean, false)
        )
      )
  );
$$;
revoke all on function public.has_org_permission(uuid, text) from public, anon;
grant execute on function public.has_org_permission(uuid, text) to authenticated;
