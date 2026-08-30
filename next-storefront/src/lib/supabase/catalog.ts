import "server-only";

import { createClient } from "@supabase/supabase-js";

const STORAGE_HOST = "rglbfizqolrenwfsndyv.supabase.co";

export type StoreSection = {
  id: string;
  name: string;
  displayOrder: number;
};

export type StoreCategory = {
  id: string;
  sectionId: string;
  name: string;
  description: string | null;
  imageUrl: string | null;
  displayOrder: number;
  productCount: number;
};

export type Catalog = {
  configured: boolean;
  sections: StoreSection[];
  categories: StoreCategory[];
  error: boolean;
};

type SectionRow = {
  id: string;
  name: string;
  display_order: number | null;
};

type CategoryRow = {
  id: string;
  section_id: string;
  name: string;
  description: string | null;
  image_url: string | null;
  display_order: number | null;
};

type ProductRow = { category_id: string | null };

function getSupabaseConfig() {
  const url = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key =
    process.env.SUPABASE_PUBLISHABLE_KEY ??
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ??
    process.env.SUPABASE_ANON_KEY ??
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  return url && key ? { url, key } : null;
}

function safeCatalogImage(value: string | null) {
  if (!value) return null;

  try {
    const url = new URL(value);
    const isPublicStorageObject = url.pathname.startsWith("/storage/v1/object/public/");

    if (url.protocol !== "https:" || url.hostname !== STORAGE_HOST || !isPublicStorageObject) {
      return null;
    }

    return url.toString();
  } catch {
    return null;
  }
}

export async function getCatalog(): Promise<Catalog> {
  const config = getSupabaseConfig();

  if (!config) {
    return { configured: false, sections: [], categories: [], error: false };
  }

  const supabase = createClient(config.url, config.key, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });

  const [sectionsResult, categoriesResult, productsResult] = await Promise.all([
    supabase
      .from("store_sections")
      .select("id,name,display_order")
      .eq("is_active", true)
      .order("display_order")
      .order("name"),
    supabase
      .from("categories")
      .select("id,section_id,name,description,image_url,display_order")
      .eq("is_active", true)
      .not("section_id", "is", null)
      .order("display_order")
      .order("name"),
    supabase.from("products").select("category_id").eq("is_active", true),
  ]);

  if (sectionsResult.error || categoriesResult.error || productsResult.error) {
    return { configured: true, sections: [], categories: [], error: true };
  }

  const productCounts = new Map<string, number>();

  for (const product of (productsResult.data ?? []) as ProductRow[]) {
    if (!product.category_id) continue;
    productCounts.set(product.category_id, (productCounts.get(product.category_id) ?? 0) + 1);
  }

  const sections = ((sectionsResult.data ?? []) as SectionRow[]).map((section) => ({
    id: section.id,
    name: section.name,
    displayOrder: section.display_order ?? 0,
  }));

  const categories = ((categoriesResult.data ?? []) as CategoryRow[]).map((category) => ({
    id: category.id,
    sectionId: category.section_id,
    name: category.name,
    description: category.description,
    imageUrl: safeCatalogImage(category.image_url),
    displayOrder: category.display_order ?? 0,
    productCount: productCounts.get(category.id) ?? 0,
  }));

  return { configured: true, sections, categories, error: false };
}
