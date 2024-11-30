import Image from "next/image";
import { Inter } from "next/font/google";
import { extract, ArticleData } from '@extractus/article-extractor'
import { useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Button } from "@/components/ui/button"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"

const inter = Inter({ subsets: ["latin"] });

const API_BASE = 'https://api.nytimes.com/svc'
const API_KEY = "D98fzHKIasicyVeGA8a6nrWtCSpZZEVr"

interface NYTArticle {
  headline: { main: string };
  abstract: string;
  web_url: string;
  pub_date: string;
  byline?: { original: string };
  multimedia?: Array<{
    url: string;
    type: string;
  }>;
}

async function fetchNYTArticles(query: string, options: any = {}) {
  const {
    page = 0,
    sort = 'newest',
    beginDate,
    endDate
  } = options;

  const params = new URLSearchParams({
    'api-key': API_KEY,
    'q': query,
    'page': page.toString(),
    'sort': sort
  });

  if (beginDate) params.append('begin_date', beginDate);
  if (endDate) params.append('end_date', endDate);

  const endpoint = `${API_BASE}/search/v2/articlesearch.json?${params.toString()}`;

  const response = await fetch(endpoint);
  if (!response.ok) throw new Error('Network response was not ok');
  const data = await response.json();
  console.log(data.response.docs);
  return data.response.docs;
}



export default function Home() {
  const [query, setQuery] = useState('');
  const [articleUrl, setArticleUrl] = useState('');
  const [articleId, setArticleId] = useState('');
  const [articles, setArticles] = useState<NYTArticle[]>([]);
  const [specificArticle, setSpecificArticle] = useState<NYTArticle | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleKeywordSearch = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError('');
    setSpecificArticle(null);
    
    try {
      const results = await fetchNYTArticles(query);
      setArticles(results);
    } catch (err) {
      setError('検索中にエラーが発生しました');
      console.error(err);
    }
    
    setLoading(false);
  };

  const handleUrlSearch = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError('');
    setArticles([]);
    
    try {
      const result = await fetchNYTArticleByUrl(articleUrl);
      if (result) {
        setSpecificArticle(result);
      } else {
        setError('記事が見つかりませんでした');
      }
    } catch (err) {
      setError('記事の取得中にエラーが発生しました');
      console.error(err);
    }
    
    setLoading(false);
  };

  const handleIdSearch = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError('');
    setArticles([]);
    
    try {
      const result = await fetchNYTArticleById(articleId);
      if (result) {
        setSpecificArticle(result);
      } else {
        setError('記事が見つかりませんでした');
      }
    } catch (err) {
      setError('記事の取得中にエラーが発生しました');
      console.error(err);
    }
    
    setLoading(false);
  };

  const renderArticle = (article: NYTArticle) => (
    <Card className="mb-4">
      <CardHeader>
        <CardTitle>{article.headline.main}</CardTitle>
        {article.byline && (
          <div className="text-sm text-gray-500">
            {article.byline.original}
          </div>
        )}
        <div className="text-sm text-gray-500">
          公開日: {new Date(article.pub_date).toLocaleDateString()}
        </div>
      </CardHeader>
      <CardContent>
        {article.multimedia?.length > 0 && (
          <div className="mb-4 relative w-full h-64">
            <Image
              src={`https://www.nytimes.com/${article.multimedia[0].url}`}
              alt={article.headline.main}
              fill
              className="object-cover rounded-lg"
            />
          </div>
        )}
        <p className="text-gray-700 mb-4">{article.abstract}</p>
        <Button
          variant="outline"
          onClick={() => window.open(article.web_url, '_blank')}
        >
          記事を読む
        </Button>
      </CardContent>
    </Card>
  );

  return (
    <main className={`min-h-screen p-8 ${inter.className}`}>
      <div className="max-w-4xl mx-auto">
        <h1 className="text-3xl font-bold mb-8">NYT記事検索</h1>
        
        <Tabs defaultValue="keyword" className="mb-8">
          <TabsList className="grid w-full grid-cols-3">
            <TabsTrigger value="keyword">キーワード検索</TabsTrigger>
            <TabsTrigger value="url">URL検索</TabsTrigger>
            <TabsTrigger value="id">ID検索</TabsTrigger>
          </TabsList>
          
          <TabsContent value="keyword">
            <Card>
              <CardHeader>
                <CardTitle>キーワードで検索</CardTitle>
              </CardHeader>
              <CardContent>
                <form onSubmit={handleKeywordSearch} className="flex gap-4">
                  <Input
                    type="text"
                    value={query}
                    onChange={(e) => setQuery(e.target.value)}
                    placeholder="検索キーワード"
                    className="flex-1"
                    required
                  />
                  <Button type="submit" disabled={loading}>
                    {loading ? '検索中...' : '検索'}
                  </Button>
                </form>
              </CardContent>
            </Card>
          </TabsContent>
          
          <TabsContent value="url">
            <Card>
              <CardHeader>
                <CardTitle>URLで記事を検索</CardTitle>
              </CardHeader>
              <CardContent>
                <form onSubmit={handleUrlSearch} className="flex gap-4">
                  <Input
                    type="url"
                    value={articleUrl}
                    onChange={(e) => setArticleUrl(e.target.value)}
                    placeholder="https://www.nytimes.com/..."
                    className="flex-1"
                    required
                  />
                  <Button type="submit" disabled={loading}>
                    {loading ? '取得中...' : '記事を取得'}
                  </Button>
                </form>
              </CardContent>
            </Card>
          </TabsContent>
          
          <TabsContent value="id">
            <Card>
              <CardHeader>
                <CardTitle>記事IDで検索</CardTitle>
              </CardHeader>
              <CardContent>
                <form onSubmit={handleIdSearch} className="flex gap-4">
                  <Input
                    type="text"
                    value={articleId}
                    onChange={(e) => setArticleId(e.target.value)}
                    placeholder="nyt://article/..."
                    className="flex-1"
                    required
                  />
                  <Button type="submit" disabled={loading}>
                    {loading ? '取得中...' : '記事を取得'}
                  </Button>
                </form>
              </CardContent>
            </Card>
          </TabsContent>
        </Tabs>

        {error && (
          <div className="text-red-500 mb-4">{error}</div>
        )}

        {specificArticle && renderArticle(specificArticle)}
        
        {articles.map((article, index) => renderArticle(article))}
      </div>
    </main>
  );
}


async function fetchNYTArticleByUrl(articleUrl: string) {
  const params = new URLSearchParams({
    'api-key': API_KEY,
    'url': articleUrl,
    'page-size': "1"
  });

  const endpoint = `${API_BASE}/search/v2/articlesearch.json?${params.toString()}`;

  try {
    const response = await fetch(endpoint);
    if (!response.ok) throw new Error('Network response was not ok');
    const data = await response.json();
    
    // 通常、完全に一致する記事が1つだけ返されます
    if (data.response.docs.length > 0) {
      return data.response.docs[0];
    }
    return null;
  } catch (error) {
    console.error('Article fetch error:', error);
    throw error;
  }
}

// 記事IDから記事を取得する関数
// Note: この機能はTimesNewswire APIで利用可能です
async function fetchNYTArticleById(articleId: string) {
  const endpoint = `${API_BASE}/news/v3/content/${articleId}.json?api-key=${API_KEY}`;

  try {
    const response = await fetch(endpoint);
    if (!response.ok) throw new Error('Network response was not ok');
    const data = await response.json();
    return data.results[0];
  } catch (error) {
    console.error('Article fetch error:', error);
    throw error;
  }
}