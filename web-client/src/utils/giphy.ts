/**
 * GIPHY API 客户端
 * 提供 GIF 搜索、获取热门 GIF、分类浏览等功能
 */

// GIPHY API 配置
// 注意：在生产环境中应该使用后端代理来隐藏 API Key
const GIPHY_API_KEY = (import.meta as any).env?.VITE_GIPHY_API_KEY || 'your_api_key_here'
const GIPHY_API_BASE = 'https://api.giphy.com/v1/gifs'

export interface Gif {
  id: string
  url: string
  title: string
  images: {
    original: {
      url: string
      width: string
      height: string
      size: string
    }
    preview: {
      url: string
      width: string
      height: string
    }
    fixed_height: {
      url: string
      width: string
      height: string
    }
    fixed_width: {
      url: string
      width: string
      height: string
    }
  }
}

export interface GifSearchOptions {
  q?: string
  limit?: number
  offset?: number
  rating?: 'g' | 'pg' | 'pg-13' | 'r'
  lang?: string
}

/**
 * 将 API 响应转换为 Gif 类型
 */
function parseGifData(gif: any): Gif {
  return {
    id: gif.id,
    url: gif.images.original.url,
    title: gif.title || 'GIF',
    images: {
      original: {
        url: gif.images.original?.url || '',
        width: gif.images.original?.width || '0',
        height: gif.images.original?.height || '0',
        size: gif.images.original?.size || '0'
      },
      preview: {
        url: gif.images.fixed_height_downsampled?.url || gif.images.original?.url || '',
        width: gif.images.fixed_height_downsampled?.width || '0',
        height: gif.images.fixed_height_downsampled?.height || '0'
      },
      fixed_height: {
        url: gif.images.fixed_height?.url || '',
        width: gif.images.fixed_height?.width || '0',
        height: gif.images.fixed_height?.height || '0'
      },
      fixed_width: {
        url: gif.images.fixed_width?.url || '',
        width: gif.images.fixed_width?.width || '0',
        height: gif.images.fixed_width?.height || '0'
      }
    }
  }
}

/**
 * 搜索 GIF
 * @param query 搜索关键词
 * @param options 搜索选项
 */
export async function searchGifs(
  query: string,
  options: GifSearchOptions = {}
): Promise<Gif[]> {
  const params = new URLSearchParams({
    api_key: GIPHY_API_KEY,
    q: query,
    limit: (options.limit || 20).toString(),
    offset: (options.offset || 0).toString(),
    rating: options.rating || 'pg',
    lang: options.lang || 'en'
  })

  try {
    const response = await fetch(`${GIPHY_API_BASE}/search?${params}`)
    if (!response.ok) {
      throw new Error(`GIPHY API error: ${response.status}`)
    }
    const data = await response.json()
    return data.data.map(parseGifData)
  } catch (error) {
    console.error('Failed to search GIFs:', error)
    return []
  }
}

/**
 * 获取热门 GIF
 * @param options 搜索选项
 */
export async function getTrendingGifs(
  options: GifSearchOptions = {}
): Promise<Gif[]> {
  const params = new URLSearchParams({
    api_key: GIPHY_API_KEY,
    limit: (options.limit || 20).toString(),
    offset: (options.offset || 0).toString(),
    rating: options.rating || 'pg'
  })

  try {
    const response = await fetch(`${GIPHY_API_BASE}/trending?${params}`)
    if (!response.ok) {
      throw new Error(`GIPHY API error: ${response.status}`)
    }
    const data = await response.json()
    return data.data.map(parseGifData)
  } catch (error) {
    console.error('Failed to get trending GIFs:', error)
    return []
  }
}

/**
 * 按分类获取 GIF
 * @param category 分类名称（GIPHY 支持的分类）
 * @param options 搜索选项
 */
export async function getGifsByCategory(
  category: string,
  options: GifSearchOptions = {}
): Promise<Gif[]> {
  // GIPHY 支持的分类列表
  const validCategories = [
    'reactions',
    'entertainment',
    'sports',
    'animals',
    'memes',
    'love',
    'celebrations',
    'holidays',
    'food',
    'beauty',
    'fashion',
    'home',
    'inspiration',
    'learning',
    'miscellaneous',
    'news',
    'parenting',
    'science',
    'wellness'
  ]

  const normalizedCategory = category.toLowerCase()
  const targetCategory = validCategories.find(c => c.includes(normalizedCategory) || normalizedCategory.includes(c)) || 'miscellaneous'

  const params = new URLSearchParams({
    api_key: GIPHY_API_KEY,
    limit: (options.limit || 20).toString(),
    offset: (options.offset || 0).toString(),
    rating: options.rating || 'pg'
  })

  try {
    const response = await fetch(`${GIPHY_API_BASE}/categories/${targetCategory}?${params}`)
    if (!response.ok) {
      // 如果分类 API 不可用，回退到搜索
      return searchGifs(targetCategory, options)
    }
    const data = await response.json()
    return data.data.map(parseGifData)
  } catch (error) {
    console.error(`Failed to get ${category} GIFs:`, error)
    // 回退到搜索
    return searchGifs(category, options)
  }
}

/**
 * 获取随机 GIF
 * @param query 搜索关键词
 * @param rating 评级
 */
export async function getRandomGif(
  query?: string,
  rating: 'g' | 'pg' | 'pg-13' | 'r' = 'pg'
): Promise<Gif | null> {
  const params = new URLSearchParams({
    api_key: GIPHY_API_KEY,
    rating
  })

  if (query) {
    params.append('q', query)
  }

  try {
    const response = await fetch(`${GIPHY_API_BASE}/random?${params}`)
    if (!response.ok) {
      throw new Error(`GIPHY API error: ${response.status}`)
    }
    const data = await response.json()
    return parseGifData(data.data)
  } catch (error) {
    console.error('Failed to get random GIF:', error)
    return null
  }
}

/**
 * 通过 ID 获取 GIF
 * @param gifId GIF ID
 */
export async function getGifById(gifId: string): Promise<Gif | null> {
  try {
    const response = await fetch(`${GIPHY_API_BASE}/${gifId}?api_key=${GIPHY_API_KEY}`)
    if (!response.ok) {
      throw new Error(`GIPHY API error: ${response.status}`)
    }
    const data = await response.json()
    return parseGifData(data.data)
  } catch (error) {
    console.error('Failed to get GIF by ID:', error)
    return null
  }
}

/**
 * 获取 GIF 分类列表
 */
export async function getGifCategories(): Promise<string[]> {
  try {
    const response = await fetch(`${GIPHY_API_BASE}/categories?api_key=${GIPHY_API_KEY}`)
    if (!response.ok) {
      throw new Error(`GIPHY API error: ${response.status}`)
    }
    const data = await response.json()
    return data.data.map((item: any) => item.name)
  } catch (error) {
    console.error('Failed to get GIF categories:', error)
    // 返回默认分类
    return [
      'trending',
      'reactions',
      'entertainment',
      'sports',
      'animals',
      'memes',
      'love',
      'celebrations',
      'food'
    ]
  }
}

/**
 * 检查 API Key 是否配置
 */
export function isGiphyConfigured(): boolean {
  return GIPHY_API_KEY !== 'your_api_key_here' && GIPHY_API_KEY.length > 0
}
