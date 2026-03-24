"""
HTML Scraper for Schema.org Content Extraction
Scrapes HTML pages and extracts schema.org structured data for Fisterra models
"""

import requests
import json
import re
from typing import Dict, List, Any, Optional, Union, Tuple
from urllib.parse import urljoin, urlparse
from bs4 import BeautifulSoup
from datetime import datetime
import time
from schema_models import (
    SchemaOrgBase, Person, Organization, DanceGroup, Event, DanceEvent, 
    MusicEvent, EducationalEvent, Course, Place, CreativeWork
)
from pydantic import ValidationError


class SchemaOrgScraper:
    def __init__(self, base_url: str = None, delay: float = 1.0):
        """
        Initialize scraper with optional base URL and request delay
        
        Args:
            base_url: Base URL for resolving relative URLs
            delay: Delay between requests in seconds
        """
        self.base_url = base_url
        self.delay = delay
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
        })
        
    def fetch_page(self, url: str) -> Tuple[str, Dict[str, Any]]:
        """
        Fetch HTML content from URL
        
        Returns:
            Tuple of (raw_html, metadata)
        """
        try:
            response = self.session.get(url, timeout=30)
            response.raise_for_status()
            
            metadata = {
                'url': url,
                'status_code': response.status_code,
                'content_type': response.headers.get('content-type', ''),
                'content_length': len(response.content),
                'fetched_at': datetime.now().isoformat()
            }
            
            return response.text, metadata
            
        except requests.RequestException as e:
            raise Exception(f"Failed to fetch {url}: {str(e)}")
    
    def extract_json_ld(self, html: str) -> List[Dict[str, Any]]:
        """
        Extract JSON-LD structured data from HTML
        
        Returns:
            List of JSON-LD objects
        """
        soup = BeautifulSoup(html, 'html.parser')
        json_ld_scripts = soup.find_all('script', {'type': 'application/ld+json'})
        
        json_ld_objects = []
        
        for script in json_ld_scripts:
            try:
                data = json.loads(script.string)
                # Handle both single objects and arrays
                if isinstance(data, list):
                    json_ld_objects.extend(data)
                else:
                    json_ld_objects.append(data)
            except json.JSONDecodeError as e:
                print(f"Warning: Invalid JSON-LD found: {e}")
                continue
                
        return json_ld_objects
    
    def extract_microdata(self, html: str) -> List[Dict[str, Any]]:
        """
        Extract Microdata structured data from HTML
        
        Returns:
            List of microdata objects
        """
        soup = BeautifulSoup(html, 'html.parser')
        microdata_objects = []
        
        # Find elements with itemscope attribute
        items = soup.find_all(attrs={'itemscope': True})
        
        for item in items:
            obj = {}
            
            # Get itemtype
            itemtype = item.get('itemtype')
            if itemtype:
                # Extract schema.org type from URL
                if isinstance(itemtype, list):
                    itemtype = itemtype[0]
                obj['@type'] = itemtype.split('/')[-1] if '/' in itemtype else itemtype
            
            # Extract properties
            properties = item.find_all(attrs={'itemprop': True})
            for prop in properties:
                prop_name = prop.get('itemprop')
                
                # Get property value based on element type
                if prop.name in ['meta']:
                    prop_value = prop.get('content', '')
                elif prop.name in ['time']:
                    prop_value = prop.get('datetime') or prop.get_text(strip=True)
                elif prop.name in ['img']:
                    prop_value = prop.get('src', '')
                elif prop.name in ['a']:
                    prop_value = prop.get('href', '') or prop.get_text(strip=True)
                else:
                    prop_value = prop.get_text(strip=True)
                
                # Handle multiple properties with same name
                if prop_name in obj:
                    if not isinstance(obj[prop_name], list):
                        obj[prop_name] = [obj[prop_name]]
                    obj[prop_name].append(prop_value)
                else:
                    obj[prop_name] = prop_value
            
            if obj:  # Only add if we found properties
                microdata_objects.append(obj)
        
        return microdata_objects
    
    def extract_rdfa(self, html: str) -> List[Dict[str, Any]]:
        """
        Extract RDFa structured data from HTML
        
        Returns:
            List of RDFa objects  
        """
        soup = BeautifulSoup(html, 'html.parser')
        rdfa_objects = []
        
        # Find elements with typeof attribute (RDFa)
        items = soup.find_all(attrs={'typeof': True})
        
        for item in items:
            obj = {}
            
            # Get typeof
            typeof = item.get('typeof')
            if typeof:
                obj['@type'] = typeof
            
            # Extract properties
            properties = item.find_all(attrs={'property': True})
            for prop in properties:
                prop_name = prop.get('property')
                
                # Get property value
                if prop.get('content'):
                    prop_value = prop.get('content')
                elif prop.get('href'):
                    prop_value = prop.get('href')
                elif prop.get('datetime'):
                    prop_value = prop.get('datetime')
                else:
                    prop_value = prop.get_text(strip=True)
                
                obj[prop_name] = prop_value
            
            if obj:
                rdfa_objects.append(obj)
        
        return rdfa_objects
    
    def extract_meta_tags(self, html: str) -> Dict[str, Any]:
        """
        Extract relevant meta tags (Open Graph, Twitter Cards, etc.)
        
        Returns:
            Dictionary of meta tag data
        """
        soup = BeautifulSoup(html, 'html.parser')
        meta_data = {}
        
        # Standard meta tags
        standard_meta = soup.find_all('meta', attrs={'name': True, 'content': True})
        for meta in standard_meta:
            name = meta.get('name')
            content = meta.get('content')
            meta_data[f"meta_{name}"] = content
        
        # Open Graph tags
        og_meta = soup.find_all('meta', attrs={'property': lambda x: x and x.startswith('og:')})
        for meta in og_meta:
            property_name = meta.get('property')
            content = meta.get('content')
            meta_data[property_name] = content
        
        # Twitter Card tags
        twitter_meta = soup.find_all('meta', attrs={'name': lambda x: x and x.startswith('twitter:')})
        for meta in twitter_meta:
            name = meta.get('name')
            content = meta.get('content')
            meta_data[name] = content
        
        # Title and description
        title_tag = soup.find('title')
        if title_tag:
            meta_data['title'] = title_tag.get_text(strip=True)
        
        description_meta = soup.find('meta', attrs={'name': 'description'})
        if description_meta:
            meta_data['description'] = description_meta.get('content', '')
        
        return meta_data
    
    def extract_semantic_elements(self, html: str) -> Dict[str, List[Dict[str, Any]]]:
        """
        Extract semantic HTML elements that could contain structured data
        
        Returns:
            Dictionary with lists of semantic elements
        """
        soup = BeautifulSoup(html, 'html.parser')
        semantic_data = {
            'articles': [],
            'events': [],
            'addresses': [],
            'persons': [],
            'organizations': []
        }
        
        # Extract articles
        articles = soup.find_all('article')
        for article in articles:
            article_data = {
                'tag': 'article',
                'text': article.get_text(strip=True)[:500] + '...' if len(article.get_text(strip=True)) > 500 else article.get_text(strip=True),
                'classes': article.get('class', []),
                'id': article.get('id')
            }
            
            # Look for datetime
            time_elem = article.find('time')
            if time_elem:
                article_data['datetime'] = time_elem.get('datetime') or time_elem.get_text(strip=True)
            
            semantic_data['articles'].append(article_data)
        
        # Extract potential event information
        event_keywords = ['event', 'concert', 'class', 'workshop', 'performance', 'festival']
        event_elements = soup.find_all(lambda tag: any(keyword in tag.get_text().lower() for keyword in event_keywords))[:10]  # Limit results
        
        for elem in event_elements:
            if elem.name in ['script', 'style']:  # Skip script/style tags
                continue
                
            event_data = {
                'tag': elem.name,
                'text': elem.get_text(strip=True)[:200] + '...' if len(elem.get_text(strip=True)) > 200 else elem.get_text(strip=True),
                'classes': elem.get('class', []),
                'id': elem.get('id')
            }
            semantic_data['events'].append(event_data)
        
        # Extract addresses
        address_elements = soup.find_all(['address', lambda tag: 'address' in str(tag.get('class', []))])
        for addr in address_elements:
            addr_data = {
                'tag': addr.name,
                'text': addr.get_text(strip=True),
                'classes': addr.get('class', [])
            }
            semantic_data['addresses'].append(addr_data)
        
        return semantic_data
    
    def identify_schema_objects(self, all_data: Dict[str, Any]) -> Dict[str, List[Dict[str, Any]]]:
        """
        Analyze extracted data and identify potential schema.org objects
        
        Returns:
            Dictionary categorizing potential schema.org objects
        """
        identified_objects = {
            'Person': [],
            'Organization': [],
            'DanceGroup': [],
            'Event': [],
            'DanceEvent': [],
            'MusicEvent': [],
            'EducationalEvent': [],
            'Course': [],
            'Place': [],
            'CreativeWork': []
        }
        
        # Process JSON-LD data
        for obj in all_data.get('json_ld', []):
            obj_type = obj.get('@type', '').replace('https://schema.org/', '').replace('http://schema.org/', '')
            
            if obj_type in identified_objects:
                identified_objects[obj_type].append(obj)
            elif obj_type in ['PerformingGroup', 'MusicGroup']:
                identified_objects['Organization'].append(obj)
        
        # Process microdata
        for obj in all_data.get('microdata', []):
            obj_type = obj.get('@type', '')
            if obj_type in identified_objects:
                identified_objects[obj_type].append(obj)
        
        # Infer from content analysis
        meta_data = all_data.get('meta_tags', {})
        semantic_data = all_data.get('semantic_elements', {})
        
        # Look for dance/music related content
        dance_keywords = ['dance', 'salsa', 'bachata', 'tango', 'swing', 'ballroom', 'latin', 'zouk', 'kizomba']
        music_keywords = ['concert', 'music', 'performance', 'musician', 'song', 'album']
        education_keywords = ['class', 'course', 'lesson', 'workshop', 'training', 'education']
        
        page_text = ' '.join([
            meta_data.get('title', ''),
            meta_data.get('description', ''),
            meta_data.get('og:title', ''),
            meta_data.get('og:description', '')
        ]).lower()
        
        # Infer event types based on content
        if any(keyword in page_text for keyword in dance_keywords):
            if any(keyword in page_text for keyword in education_keywords):
                identified_objects['EducationalEvent'].append({
                    '@type': 'EducationalEvent',
                    'name': meta_data.get('title', ''),
                    'description': meta_data.get('description', ''),
                    'inferred': True,
                    'teaches': [kw for kw in dance_keywords if kw in page_text]
                })
            else:
                identified_objects['DanceEvent'].append({
                    '@type': 'DanceEvent', 
                    'name': meta_data.get('title', ''),
                    'description': meta_data.get('description', ''),
                    'inferred': True,
                    'danceStyle': [kw for kw in dance_keywords if kw in page_text]
                })
        
        elif any(keyword in page_text for keyword in music_keywords):
            identified_objects['MusicEvent'].append({
                '@type': 'MusicEvent',
                'name': meta_data.get('title', ''),
                'description': meta_data.get('description', ''),
                'inferred': True
            })
        
        return identified_objects
    
    def scrape_page(self, url: str) -> Dict[str, Any]:
        """
        Complete page scraping and analysis
        
        Returns:
            Dictionary with all extracted and analyzed data
        """
        print(f"🕷️ Scraping: {url}")
        
        # Fetch page
        raw_html, metadata = self.fetch_page(url)
        
        # Extract structured data
        json_ld = self.extract_json_ld(raw_html)
        microdata = self.extract_microdata(raw_html)
        rdfa = self.extract_rdfa(raw_html)
        meta_tags = self.extract_meta_tags(raw_html)
        semantic_elements = self.extract_semantic_elements(raw_html)
        
        # Compile all data
        all_data = {
            'url': url,
            'metadata': metadata,
            'raw_html': raw_html,
            'json_ld': json_ld,
            'microdata': microdata,
            'rdfa': rdfa,
            'meta_tags': meta_tags,
            'semantic_elements': semantic_elements,
            'scraped_at': datetime.now().isoformat()
        }
        
        # Identify schema.org objects
        schema_objects = self.identify_schema_objects(all_data)
        all_data['identified_objects'] = schema_objects
        
        # Add delay between requests
        if self.delay > 0:
            time.sleep(self.delay)
        
        return all_data
    
    def scrape_multiple_pages(self, urls: List[str]) -> Dict[str, Dict[str, Any]]:
        """
        Scrape multiple pages
        
        Returns:
            Dictionary mapping URLs to their scraped data
        """
        results = {}
        
        for url in urls:
            try:
                results[url] = self.scrape_page(url)
                print(f"  ✅ Scraped: {url}")
            except Exception as e:
                print(f"  ❌ Failed to scrape {url}: {e}")
                results[url] = {
                    'error': str(e),
                    'scraped_at': datetime.now().isoformat()
                }
        
        return results
    
    def generate_database_schema(self, scraped_data: Dict[str, Dict[str, Any]]) -> Dict[str, Any]:
        """
        Generate database schema recommendations based on scraped data
        
        Returns:
            Dictionary with schema recommendations
        """
        schema_recommendations = {
            'identified_types': set(),
            'required_tables': [],
            'suggested_relationships': [],
            'field_analysis': {},
            'recommendations': []
        }
        
        # Analyze all identified objects
        for url, data in scraped_data.items():
            if 'identified_objects' in data:
                for obj_type, objects in data['identified_objects'].items():
                    if objects:  # Only count types that have instances
                        schema_recommendations['identified_types'].add(obj_type)
                        
                        # Analyze fields in objects
                        for obj in objects:
                            if obj_type not in schema_recommendations['field_analysis']:
                                schema_recommendations['field_analysis'][obj_type] = {}
                            
                            for field, value in obj.items():
                                if field not in schema_recommendations['field_analysis'][obj_type]:
                                    schema_recommendations['field_analysis'][obj_type][field] = {
                                        'count': 0,
                                        'types': set(),
                                        'sample_values': []
                                    }
                                
                                field_info = schema_recommendations['field_analysis'][obj_type][field]
                                field_info['count'] += 1
                                field_info['types'].add(type(value).__name__)
                                
                                if len(field_info['sample_values']) < 3:
                                    field_info['sample_values'].append(str(value)[:100])
        
        # Convert sets to lists for JSON serialization
        schema_recommendations['identified_types'] = list(schema_recommendations['identified_types'])
        
        for obj_type, fields in schema_recommendations['field_analysis'].items():
            for field, info in fields.items():
                info['types'] = list(info['types'])
        
        # Generate table recommendations
        for obj_type in schema_recommendations['identified_types']:
            table_name = f"{obj_type.lower()}s"
            schema_recommendations['required_tables'].append({
                'table_name': table_name,
                'schema_type': obj_type,
                'fields': list(schema_recommendations['field_analysis'].get(obj_type, {}).keys())
            })
        
        # Generate relationship recommendations
        if 'Event' in schema_recommendations['identified_types'] and 'Person' in schema_recommendations['identified_types']:
            schema_recommendations['suggested_relationships'].append('Event -> Person (performers, instructors)')
        
        if 'Event' in schema_recommendations['identified_types'] and 'Place' in schema_recommendations['identified_types']:
            schema_recommendations['suggested_relationships'].append('Event -> Place (location)')
        
        if 'Person' in schema_recommendations['identified_types'] and 'Organization' in schema_recommendations['identified_types']:
            schema_recommendations['suggested_relationships'].append('Person -> Organization (membership)')
        
        return schema_recommendations


def main():
    """Example usage"""
    scraper = SchemaOrgScraper(delay=1.0)
    
    # Example URLs - replace with actual site URLs
    test_urls = [
        "https://schema.org/Event",  # Schema.org example
        "https://schema.org/Person",
        "https://schema.org/Organization"
    ]
    
    print("🎭 Starting Schema.org Content Scraper")
    print("=" * 50)
    
    # Scrape pages
    results = scraper.scrape_multiple_pages(test_urls)
    
    # Generate schema recommendations
    schema_recs = scraper.generate_database_schema(results)
    
    print("\\n📊 Schema Analysis Complete")
    print(f"Identified types: {', '.join(schema_recs['identified_types'])}")
    print(f"Recommended tables: {len(schema_recs['required_tables'])}")
    
    # Save results
    with open('scraping_results.json', 'w') as f:
        json.dump(results, f, indent=2, default=str)
    
    with open('schema_recommendations.json', 'w') as f:
        json.dump(schema_recs, f, indent=2, default=str)
    
    print("\\n💾 Results saved to:")
    print("  - scraping_results.json")  
    print("  - schema_recommendations.json")


if __name__ == "__main__":
    main()