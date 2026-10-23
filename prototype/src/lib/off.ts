import { GRAMS_TO_UNIT, NUTRIENTS, type Nutrients } from './nutrients'
import type { Food, Serving } from './types'

/**
 * OpenFoodFacts access.
 * - Search uses search.openfoodfacts.org (fast, Elasticsearch-backed) through the Vite proxy,
 *   falling back to the legacy CORS-enabled cgi/search.pl when the proxy is unavailable.
 * - Product details use the v2 product API directly (it sends CORS headers). Search hits only
 *   carry macros, so the full product is fetched when a food is selected.
 */

const SEARCH_URL = '/off-search/search'
const LEGACY_SEARCH_URL = 'https://world.openfoodfacts.org/cgi/search.pl'
const PRODUCT_URL = 'https://world.openfoodfacts.org/api/v2/product'
const PAGE_SIZE = 30

const SEARCH_FIELDS = 'code,product_name,product_name_en,brands,image_front_small_url,nutriments,quantity'
const PRODUCT_FIELDS = [
  'code',
  'product_name',
  'product_name_en',
  'brands',
  'image_front_small_url',
  'serving_size',
  'serving_quantity',
  'serving_quantity_unit',
  'product_quantity',
  'product_quantity_unit',
  'quantity',
  'nutriments',
].join(',')

interface OffProduct {
  code?: string
  product_name?: string
  product_name_en?: string
  brands?: string | string[]
  image_front_small_url?: string
  serving_size?: string
  serving_quantity?: number | string
  serving_quantity_unit?: string
  product_quantity?: number | string
  product_quantity_unit?: string
  quantity?: string
  nutriments?: Record<string, number | string | undefined>
}

export interface SearchPage {
  foods: Food[]
  hasMore: boolean
}

function num(v: unknown): number | undefined {
  const n = typeof v === 'string' ? parseFloat(v) : v
  return typeof n === 'number' && Number.isFinite(n) ? n : undefined
}

function readNutrients(raw: OffProduct['nutriments'] = {}): Nutrients {
  const out: Nutrients = {}
  for (const def of NUTRIENTS) {
    if (!('off' in def)) continue
    for (const key of def.off) {
      const v = num(raw[`${key}_100g`])
      if (v !== undefined) {
        out[def.key] = v * GRAMS_TO_UNIT[def.unit]
        break
      }
    }
  }
  const kcal = num(raw['energy-kcal_100g'])
  const kj = num(raw['energy-kj_100g']) ?? num(raw['energy_100g'])
  if (kcal !== undefined) out.energy = kcal
  else if (kj !== undefined) out.energy = kj / 4.184
  if (out.sodium === undefined) {
    const salt = num(raw['salt_100g'])
    if (salt !== undefined) out.sodium = (salt / 2.5) * 1000
  }
  return out
}

function readServings(p: OffProduct): Serving[] {
  const servings: Serving[] = []
  const serving = num(p.serving_quantity)
  if (serving && serving > 0) {
    const size = p.serving_size?.trim()
    // Sizes like "30 g" become "serving (30 g)"; descriptive ones like "1 cup (240 ml)" are kept as-is.
    const label = !size ? `serving (${serving} g)` : /^[\d.,\s]*(g|gr|ml|oz)?$/i.test(size) ? `serving (${size})` : size
    servings.push({ label, grams: serving })
  }
  const pkg = num(p.product_quantity)
  if (pkg && pkg > 0 && pkg !== serving) {
    servings.push({ label: `package (${p.quantity?.trim() || `${pkg} g`})`, grams: pkg })
  }
  return servings
}

function brandOf(p: OffProduct): string | undefined {
  const b = Array.isArray(p.brands) ? p.brands[0] : p.brands?.split(',')[0]
  return b?.trim() || undefined
}

export function normalizeProduct(p: OffProduct, complete: boolean): Food | null {
  const name = (p.product_name_en || p.product_name || '').trim()
  if (!p.code || !name) return null
  return {
    id: `off:${p.code}`,
    source: 'off',
    name,
    brand: brandOf(p),
    imageUrl: p.image_front_small_url,
    barcode: p.code,
    nutrients: readNutrients(p.nutriments),
    servings: complete ? readServings(p) : [],
    complete,
  }
}

const searchCache = new Map<string, SearchPage>()

export async function searchFoods(query: string, page = 1, signal?: AbortSignal): Promise<SearchPage> {
  const q = query.trim()
  const cacheKey = `${q.toLowerCase()}|${page}`
  const cached = searchCache.get(cacheKey)
  if (cached) return cached

  let products: OffProduct[]
  let pageCount: number
  try {
    const params = new URLSearchParams({ q, page: String(page), page_size: String(PAGE_SIZE), langs: 'en', fields: SEARCH_FIELDS })
    const res = await fetch(`${SEARCH_URL}?${params}`, { signal })
    if (!res.ok || !res.headers.get('content-type')?.includes('json')) throw new Error(`search ${res.status}`)
    const data = (await res.json()) as { hits: OffProduct[]; page_count: number }
    products = data.hits
    pageCount = data.page_count
  } catch (err) {
    if (signal?.aborted) throw err
    const params = new URLSearchParams({
      search_terms: q,
      search_simple: '1',
      action: 'process',
      json: '1',
      page: String(page),
      page_size: String(PAGE_SIZE),
      fields: SEARCH_FIELDS,
    })
    const res = await fetch(`${LEGACY_SEARCH_URL}?${params}`, { signal })
    if (!res.ok) throw new Error(`OpenFoodFacts search failed (${res.status}). Try again in a moment.`)
    const data = (await res.json()) as { products: OffProduct[]; count: number }
    products = data.products
    pageCount = Math.ceil(data.count / PAGE_SIZE)
  }

  const foods = products
    .map((p) => normalizeProduct(p, false))
    .filter((f): f is Food => f !== null && f.nutrients.energy !== undefined)
  const result = { foods, hasMore: page < pageCount }
  searchCache.set(cacheKey, result)
  return result
}

const productCache = new Map<string, Food | null>()

export async function fetchProduct(barcode: string, signal?: AbortSignal): Promise<Food | null> {
  if (productCache.has(barcode)) return productCache.get(barcode)!
  const food = await fetchProductUncached(barcode, signal)
  productCache.set(barcode, food)
  return food
}

async function fetchProductUncached(barcode: string, signal?: AbortSignal): Promise<Food | null> {
  const res = await fetch(`${PRODUCT_URL}/${encodeURIComponent(barcode)}.json?fields=${PRODUCT_FIELDS}`, { signal })
  if (res.status === 404) return null
  if (!res.ok) throw new Error(`OpenFoodFacts product lookup failed (${res.status})`)
  const data = (await res.json()) as { status: number; product?: OffProduct }
  if (data.status !== 1 || !data.product) return null
  return normalizeProduct({ ...data.product, code: data.product.code ?? barcode }, true)
}

export function isBarcode(query: string): boolean {
  return /^\d{8,14}$/.test(query.trim())
}
