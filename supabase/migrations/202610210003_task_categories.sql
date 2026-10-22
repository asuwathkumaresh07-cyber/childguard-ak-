alter table public.child_tasks
  add column if not exists task_type text not null default 'task';

alter table public.child_tasks
  drop constraint if exists child_tasks_task_type_check;

alter table public.child_tasks
  add constraint child_tasks_task_type_check
  check (task_type in ('task', 'homework'));
