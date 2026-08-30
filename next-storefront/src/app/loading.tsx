import { Skeleton } from "@/components/ui/skeleton";

export default function Loading() {
  return (
    <main className="container-shell py-8 sm:py-12">
      <div className="grid min-h-[560px] gap-5 rounded-[2rem] border border-border bg-accent p-5 lg:grid-cols-2">
        <div className="flex flex-col justify-center gap-5 px-2 py-8 sm:px-6">
          <Skeleton className="h-7 w-40" />
          <Skeleton className="h-14 w-full max-w-xl" />
          <Skeleton className="h-14 w-4/5 max-w-lg" />
          <Skeleton className="h-24 w-full max-w-xl" />
          <div className="flex gap-3"><Skeleton className="h-13 w-36" /><Skeleton className="h-13 w-32" /></div>
        </div>
        <Skeleton className="min-h-96 rounded-[1.5rem] bg-foreground/10" />
      </div>
    </main>
  );
}
