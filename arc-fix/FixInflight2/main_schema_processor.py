"""
Main Schema.org Data Processing Pipeline for Fisterra
Coordinates scraping, analysis, and database initialization
"""

import json
import argparse
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Any, Optional

from html_scraper import SchemaOrgScraper
from sql_db_init import SQLDatabaseInitializer
from graph_db_init import Neo4jGraphInitializer
from schema_models import *


class FisterraSchemaProcessor:
    """Main coordinator for schema.org data processing"""
    
    def __init__(self, config: Dict[str, Any] = None):
        """Initialize with configuration"""
        self.config = config or self.get_default_config()
        self.scraper = SchemaOrgScraper(delay=self.config.get('scraping', {}).get('delay', 1.0))
        self.results_dir = Path(self.config.get('output_dir', 'schema_results'))
        self.results_dir.mkdir(exist_ok=True)
        
    def get_default_config(self) -> Dict[str, Any]:
        """Get default configuration"""
        return {
            'scraping': {
                'delay': 1.0,  # Seconds between requests
                'timeout': 30,
                'max_retries': 3
            },
            'databases': {
                'sql': {
                    'enabled': True,
                    'path': 'fisterra_schema.db'
                },
                'neo4j': {
                    'enabled': False,  # Disabled by default since it requires Neo4j server
                    'uri': 'bolt://localhost:7687',
                    'user': 'neo4j',
                    'password': 'password'
                }
            },
            'output_dir': 'schema_results',
            'save_raw_html': False  # Set to True to save raw HTML content
        }
    
    def scrape_site_pages(self, urls: List[str]) -> Dict[str, Dict[str, Any]]:
        """Scrape multiple pages and analyze content"""
        print(f"🕷️ Scraping {len(urls)} pages...")
        
        results = self.scraper.scrape_multiple_pages(urls)
        
        # Save raw results
        raw_results_file = self.results_dir / 'raw_scraping_results.json'
        
        # Prepare results for JSON serialization (remove raw HTML if configured)
        json_safe_results = {}
        for url, data in results.items():
            json_safe_data = data.copy()
            if not self.config.get('save_raw_html', False):
                json_safe_data.pop('raw_html', None)
            json_safe_results[url] = json_safe_data
        
        with open(raw_results_file, 'w', encoding='utf-8') as f:
            json.dump(json_safe_results, f, indent=2, default=str, ensure_ascii=False)
        
        print(f"  💾 Raw results saved to: {raw_results_file}")
        return results
    
    def analyze_schema_objects(self, scraping_results: Dict[str, Dict[str, Any]]) -> Dict[str, Any]:
        """Analyze scraped data and generate schema recommendations"""
        print("\\n📊 Analyzing schema.org objects...")
        
        analysis = {
            'summary': {
                'total_pages_scraped': len(scraping_results),
                'successful_scrapes': len([r for r in scraping_results.values() if 'error' not in r]),
                'failed_scrapes': len([r for r in scraping_results.values() if 'error' in r]),
                'analysis_date': datetime.now().isoformat()
            },
            'identified_objects': {},
            'object_counts': {},
            'field_analysis': {},
            'database_recommendations': {}
        }
        
        # Collect all identified objects
        all_objects = {}
        for url, data in scraping_results.items():
            if 'error' in data:
                continue
                
            identified = data.get('identified_objects', {})
            for obj_type, objects in identified.items():
                if objects:
                    if obj_type not in all_objects:
                        all_objects[obj_type] = []
                    all_objects[obj_type].extend(objects)
        
        analysis['identified_objects'] = all_objects
        analysis['object_counts'] = {k: len(v) for k, v in all_objects.items()}
        
        # Generate database schema recommendations
        schema_recs = self.scraper.generate_database_schema(scraping_results)
        analysis['database_recommendations'] = schema_recs
        
        # Save analysis
        analysis_file = self.results_dir / 'schema_analysis.json'
        with open(analysis_file, 'w', encoding='utf-8') as f:
            json.dump(analysis, f, indent=2, default=str, ensure_ascii=False)
        
        print(f"  📊 Object types found: {', '.join([f'{k}({v})' for k, v in analysis['object_counts'].items() if v > 0])}")
        print(f"  💾 Analysis saved to: {analysis_file}")
        
        return analysis
    
    def initialize_sql_database(self, force_recreate: bool = False) -> bool:
        """Initialize SQL database with schema"""
        if not self.config['databases']['sql']['enabled']:
            print("\\n⏭️ SQL database initialization skipped (disabled in config)")
            return False
            
        print("\\n🗄️ Initializing SQL database...")
        
        db_path = self.config['databases']['sql']['path']
        
        # Remove existing database if force recreate
        if force_recreate:
            db_file = Path(db_path)
            if db_file.exists():
                db_file.unlink()
                print(f"  🗑️ Removed existing database: {db_path}")
        
        try:
            initializer = SQLDatabaseInitializer(db_path)
            initializer.initialize_database()
            initializer.close()
            print(f"  ✅ SQL database initialized: {db_path}")
            return True
        except Exception as e:
            print(f"  ❌ SQL database initialization failed: {e}")
            return False
    
    def initialize_graph_database(self, force_recreate: bool = False) -> bool:
        """Initialize Neo4j graph database"""
        if not self.config['databases']['neo4j']['enabled']:
            print("\\n⏭️ Graph database initialization skipped (disabled in config)")
            print("  💡 To enable: install Neo4j, update config, and set enabled=True")
            return False
            
        print("\\n🕸️ Initializing Neo4j graph database...")
        
        try:
            neo4j_config = self.config['databases']['neo4j']
            initializer = Neo4jGraphInitializer(
                uri=neo4j_config['uri'],
                user=neo4j_config['user'],
                password=neo4j_config['password']
            )
            
            initializer.initialize_database()
            initializer.close()
            print("  ✅ Graph database initialized")
            return True
        except Exception as e:
            print(f"  ❌ Graph database initialization failed: {e}")
            print("  💡 Make sure Neo4j is running and credentials are correct")
            return False
    
    def generate_report(self, analysis: Dict[str, Any]) -> str:
        """Generate a comprehensive report"""
        report = []
        report.append("# Fisterra Schema.org Analysis Report")
        report.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        report.append("")
        
        # Summary
        summary = analysis['summary']
        report.append("## Summary")
        report.append(f"- **Pages Scraped**: {summary['total_pages_scraped']}")
        report.append(f"- **Successful**: {summary['successful_scrapes']}")
        report.append(f"- **Failed**: {summary['failed_scrapes']}")
        report.append("")
        
        # Object counts
        report.append("## Schema.org Objects Found")
        object_counts = analysis['object_counts']
        if any(count > 0 for count in object_counts.values()):
            for obj_type, count in object_counts.items():
                if count > 0:
                    report.append(f"- **{obj_type}**: {count} instances")
        else:
            report.append("No explicit schema.org objects found in scraped content.")
            report.append("Objects may be inferred from content analysis.")
        report.append("")
        
        # Database recommendations
        db_recs = analysis.get('database_recommendations', {})
        if db_recs.get('identified_types'):
            report.append("## Database Recommendations")
            report.append("### Identified Schema Types")
            for schema_type in db_recs['identified_types']:
                report.append(f"- {schema_type}")
            report.append("")
            
            if db_recs.get('required_tables'):
                report.append("### Recommended Tables")
                for table in db_recs['required_tables']:
                    report.append(f"- **{table['table_name']}** ({table['schema_type']})")
                    if table.get('fields'):
                        report.append(f"  - Fields: {', '.join(table['fields'][:5])}")  # Show first 5 fields
                        if len(table['fields']) > 5:
                            report.append(f"  - ... and {len(table['fields']) - 5} more")
                report.append("")
        
        # Next steps
        report.append("## Next Steps")
        report.append("1. **Review identified objects** - Check if the detected schema.org types match your content")
        report.append("2. **Customize models** - Modify `schema_models.py` for your specific needs") 
        report.append("3. **Initialize databases** - Run with `--init-sql` or `--init-neo4j` flags")
        report.append("4. **Import data** - Use the scraping results to populate your databases")
        report.append("5. **Validate relationships** - Ensure object relationships are correctly identified")
        report.append("")
        
        # Files generated
        report.append("## Generated Files")
        report.append("- `schema_models.py` - Pydantic models for schema.org objects")
        report.append("- `sql_db_init.py` - SQL database initialization")
        report.append("- `graph_db_init.py` - Neo4j graph database initialization")
        report.append("- `html_scraper.py` - HTML scraping and schema.org extraction")
        report.append("- `schema_results/` - Analysis results and data")
        
        report_text = "\\n".join(report)
        
        # Save report
        report_file = self.results_dir / 'analysis_report.md'
        with open(report_file, 'w', encoding='utf-8') as f:
            f.write(report_text)
        
        print(f"\\n📋 Report generated: {report_file}")
        return report_text
    
    def run_full_pipeline(self, urls: List[str], init_sql: bool = True, init_neo4j: bool = False) -> Dict[str, Any]:
        """Run the complete schema processing pipeline"""
        print("🎭 Starting Fisterra Schema.org Processing Pipeline")
        print("=" * 60)
        
        pipeline_results = {
            'start_time': datetime.now().isoformat(),
            'config': self.config,
            'urls': urls,
            'steps_completed': [],
            'steps_failed': []
        }
        
        try:
            # Step 1: Scrape pages
            scraping_results = self.scrape_site_pages(urls)
            pipeline_results['steps_completed'].append('scraping')
            pipeline_results['scraping_results'] = {
                'total_pages': len(scraping_results),
                'successful': len([r for r in scraping_results.values() if 'error' not in r])
            }
            
            # Step 2: Analyze schema objects
            analysis = self.analyze_schema_objects(scraping_results)
            pipeline_results['steps_completed'].append('analysis')
            pipeline_results['analysis'] = analysis
            
            # Step 3: Initialize databases
            if init_sql:
                sql_success = self.initialize_sql_database(force_recreate=True)
                if sql_success:
                    pipeline_results['steps_completed'].append('sql_init')
                else:
                    pipeline_results['steps_failed'].append('sql_init')
            
            if init_neo4j:
                neo4j_success = self.initialize_graph_database()
                if neo4j_success:
                    pipeline_results['steps_completed'].append('neo4j_init')
                else:
                    pipeline_results['steps_failed'].append('neo4j_init')
            
            # Step 4: Generate report
            report = self.generate_report(analysis)
            pipeline_results['steps_completed'].append('report')
            
        except Exception as e:
            print(f"\\n❌ Pipeline failed: {e}")
            pipeline_results['error'] = str(e)
            raise
        
        finally:
            pipeline_results['end_time'] = datetime.now().isoformat()
            
            # Save pipeline results
            pipeline_file = self.results_dir / 'pipeline_results.json'
            with open(pipeline_file, 'w', encoding='utf-8') as f:
                json.dump(pipeline_results, f, indent=2, default=str, ensure_ascii=False)
        
        print("\\n✅ Pipeline completed successfully!")
        print(f"📁 Results saved in: {self.results_dir}")
        
        return pipeline_results


def main():
    """Command line interface"""
    parser = argparse.ArgumentParser(
        description="Fisterra Schema.org Data Processing Pipeline",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Analyze example schema.org pages
  python main_schema_processor.py --demo
  
  # Scrape and analyze specific URLs
  python main_schema_processor.py --urls https://example.com/event https://example.com/about
  
  # Full pipeline with database initialization
  python main_schema_processor.py --demo --init-sql --init-neo4j
  
  # Load URLs from file
  python main_schema_processor.py --urls-file urls.txt --init-sql
        """
    )
    
    # URL input options
    url_group = parser.add_mutually_exclusive_group(required=True)
    url_group.add_argument('--urls', nargs='+', help='URLs to scrape and analyze')
    url_group.add_argument('--urls-file', help='File containing URLs (one per line)')
    url_group.add_argument('--demo', action='store_true', help='Run with demo schema.org URLs')
    
    # Database options
    parser.add_argument('--init-sql', action='store_true', help='Initialize SQL database')
    parser.add_argument('--init-neo4j', action='store_true', help='Initialize Neo4j database')
    
    # Configuration options
    parser.add_argument('--config', help='Path to JSON configuration file')
    parser.add_argument('--output-dir', help='Output directory for results')
    parser.add_argument('--delay', type=float, default=1.0, help='Delay between requests (seconds)')
    
    args = parser.parse_args()
    
    # Load configuration
    config = None
    if args.config:
        with open(args.config, 'r') as f:
            config = json.load(f)
    
    # Initialize processor
    processor = FisterraSchemaProcessor(config)
    
    # Override config with command line args
    if args.output_dir:
        processor.config['output_dir'] = args.output_dir
        processor.results_dir = Path(args.output_dir)
        processor.results_dir.mkdir(exist_ok=True)
    
    if args.delay:
        processor.config['scraping']['delay'] = args.delay
        processor.scraper.delay = args.delay
    
    # Get URLs to process
    if args.demo:
        urls = [
            "https://schema.org/Event",
            "https://schema.org/Person", 
            "https://schema.org/Organization",
            "https://schema.org/DanceEvent",
            "https://schema.org/MusicEvent",
            "https://schema.org/Course"
        ]
        print("🎭 Running demo with Schema.org example pages")
    elif args.urls_file:
        with open(args.urls_file, 'r') as f:
            urls = [line.strip() for line in f if line.strip() and not line.startswith('#')]
    else:
        urls = args.urls
    
    print(f"📋 Processing {len(urls)} URLs")
    
    # Run pipeline
    try:
        results = processor.run_full_pipeline(
            urls=urls,
            init_sql=args.init_sql,
            init_neo4j=args.init_neo4j
        )
        
        print("\\n🎉 Processing complete! Check the following files:")
        print(f"  📋 Analysis Report: {processor.results_dir}/analysis_report.md")
        print(f"  📊 Detailed Results: {processor.results_dir}/schema_analysis.json")
        print(f"  🕷️ Raw Scraping Data: {processor.results_dir}/raw_scraping_results.json")
        
    except Exception as e:
        print(f"\\n❌ Error: {e}")
        return 1
    
    return 0


if __name__ == "__main__":
    exit(main())