import requests
from urllib.parse import urlencode
import re
from newspaper import Article

# NYT APIのエンドポイント定数
API_BASE = 'https://api.nytimes.com/svc'
API_KEY = "D98fzHKIasicyVeGA8a6nrWtCSpZZEVr"

class NYTClient:
    def __init__(self, api_key):
        self.api_key = api_key

    async def get_archive(self, year, month):
        """アーカイブから特定の年月の記事を取得"""
        endpoint = f"{API_BASE}/archive/v1/{year}/{month}.json?api-key={self.api_key}"
        try:
            response = requests.get(endpoint)
            response.raise_for_status()
            data = response.json()
            return data['response']['docs']
        except Exception as error:
            print('Archive fetch error:', error)
            raise

    async def search_articles(self, query, options=None):
        """キーワードで記事を検索"""
        if options is None:
            options = {}
            
        page = options.get('page', 0)
        sort = options.get('sort', 'newest')
        begin_date = options.get('beginDate')
        end_date = options.get('endDate')

        params = {
            'api-key': self.api_key,
            'q': query,
            'page': page,
            'sort': sort
        }

        if begin_date:
            params['begin_date'] = begin_date
        if end_date:
            params['end_date'] = end_date

        endpoint = f"{API_BASE}/search/v2/articlesearch.json?{urlencode(params)}"

        try:
            response = requests.get(endpoint)
            response.raise_for_status()
            data = response.json()
            return data['response']['docs']
        except Exception as error:
            print('Search error:', error)
            raise

    async def get_article_content(self, url):
        article = Article(url)
        # 記事をダウンロードして解析
        article.download()
        article.parse()

        # タイトルと本文を表示
        print(f"タイトル: {article.title}")
        print(f"本文: {article.text}...")  


    def format_article(self, article):
        """記事の詳細情報を整形"""
        return {
            'headline': article['headline']['main'],
            'abstract': article['abstract'],
            'web_url': article['web_url'],
            'publish_date': article['pub_date'],
            'section': article['section_name'],
            'keywords': [k['value'] for k in article.get('keywords', [])]
        }

async def example():
    """使用例"""
    client = NYTClient(API_KEY)
    
    try:
        # キーワード検索の例
        print('\nSearching for articles about "2024 US election"...')
        search_results = await client.search_articles('United States Politics and Government', {
            'beginDate': '20241101',
            'endDate': '20241111'
        })
        
        # 各記事の内容を取得
        for result in search_results[0:2]:
            print('\nResult:\n\n\n', result)
            formatted_article = client.format_article(result)
            print('\nArticle:', formatted_article)
            
            # 記事のコンテンツを取得
            await client.get_article_content(formatted_article['web_url'])
                
    except Exception as error:
        print('Error:', error)

# 実行するには非同期ランタイムが必要
if __name__ == "__main__":
    import asyncio
    asyncio.run(example())