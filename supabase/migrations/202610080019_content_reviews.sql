create table public.content_reviews (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  content_item_id uuid not null,
  reviewer_id uuid not null default auth.uid() references auth.users(id) on delete restrict,
  decision text not null check (decision in ('comment', 'approved', 'changes_requested')),
  feedback text not null default '',
  created_at timestamptz not null default now(),
  foreign key (organization_id, content_item_id)
    references public.content_items(organization_id, id) on delete cascade,
  check (char_length(feedback) <= 3000)
);

create index content_reviews_item_created_idx
  on public.content_reviews (organization_id, content_item_id, created_at desc);

revoke all on public.content_reviews from anon, authenticated;
grant select on public.content_reviews to authenticated;
alter table public.content_reviews enable row level security;
create policy content_reviews_read on public.content_reviews
  for select to authenticated using (public.is_org_member(organization_id));

create trigger audit_content_reviews_insert
  after insert on public.content_reviews
  for each row execute function public.write_audit_log();

create or replace function public.submit_content_review(
  target_org uuid,
  target_item uuid,
  review_decision text,
  review_feedback text default ''
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  current_status public.content_status;
  new_review_id uuid;
  feedback_text text := btrim(coalesce(review_feedback, ''));
begin
  if actor is null or not public.has_org_permission(target_org, 'workspace.write') then
    raise exception 'Workspace write permission required';
  end if;
  if review_decision not in ('comment', 'approved', 'changes_requested') then
    raise exception 'Invalid review decision';
  end if;
  if char_length(feedback_text) > 3000 then raise exception 'Review feedback is too long'; end if;
  if review_decision in ('comment', 'changes_requested') and feedback_text = '' then
    raise exception 'Feedback is required for this review decision';
  end if;

  select item.status into current_status
    from public.content_items item
    where item.organization_id = target_org and item.id = target_item
    for update;
  if current_status is null then raise exception 'Content item not found'; end if;
  if review_decision in ('approved', 'changes_requested') and current_status <> 'review' then
    raise exception 'Only content in review can be approved or sent back';
  end if;

  insert into public.content_reviews (organization_id, content_item_id, reviewer_id, decision, feedback)
    values (target_org, target_item, actor, review_decision, feedback_text)
    returning id into new_review_id;

  if review_decision = 'approved' then
    update public.content_items set status = 'approved' where organization_id = target_org and id = target_item;
  elsif review_decision = 'changes_requested' then
    update public.content_items set status = 'review', scheduled_at = null, published_at = null
      where organization_id = target_org and id = target_item;
  end if;
  return new_review_id;
end;
$$;

revoke all on function public.submit_content_review(uuid, uuid, text, text) from public, anon;
grant execute on function public.submit_content_review(uuid, uuid, text, text) to authenticated;
