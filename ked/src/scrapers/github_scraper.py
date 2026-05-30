"""GitHub scraper for user profile data.

Extracts:
- Username and profile information
- Programming languages used
- Repository statistics (stars, forks, contributors)
- Contribution graph and activity
- Popular repositories and their topics
"""

import logging
from typing import Optional, Dict, List
from dataclasses import dataclass
from datetime import datetime

logger = logging.getLogger(__name__)


@dataclass
class GitHubRepository:
    """GitHub repository information."""
    name: str
    description: str
    url: str
    stars: int
    forks: int
    language: str
    topics: List[str]
    is_fork: bool = False


@dataclass
class GitHubProfile:
    """GitHub profile data."""
    username: str
    name: Optional[str]
    bio: Optional[str]
    follower_count: int
    following_count: int
    public_repo_count: int
    location: Optional[str] = None
    blog_url: Optional[str] = None
    twitter: Optional[str] = None
    email: Optional[str] = None
    created_at: Optional[datetime] = None
    repositories: List[GitHubRepository] = None
    
    @property
    def total_stars(self) -> int:
        """Sum of all repository stars."""
        if not self.repositories:
            return 0
        return sum(r.stars for r in self.repositories)
    
    @property
    def avg_stars_per_repo(self) -> float:
        """Average stars per repository."""
        if not self.repositories or len(self.repositories) == 0:
            return 0.0
        return self.total_stars / len(self.repositories)


class GitHubScraper:
    """Scrapes GitHub profile data using public GitHub API."""
    
    def __init__(self):
        """Initialize GitHub scraper."""
        self.base_url = "https://api.github.com"
        
        logger.info("Initialized GitHub scraper")
    
    async def scrape_profile(self, username: str) -> Optional[GitHubProfile]:
        """Scrape GitHub profile using public API (no auth required).
        
        Args:
            username: GitHub username
            
        Returns:
            GitHubProfile or None if not found
        """
        try:
            import aiohttp
            logger.info(f"Scraping GitHub profile: {username}")
            
            async with aiohttp.ClientSession() as session:
                # Fetch user profile
                async with session.get(
                    f"{self.base_url}/users/{username}",
                    headers={"Accept": "application/vnd.github.v3+json"},
                    timeout=aiohttp.ClientTimeout(total=10),
                ) as resp:
                    if resp.status != 200:
                        logger.warning(f"GitHub API returned {resp.status} for {username}")
                        return None
                    user_data = await resp.json()
                
                # Fetch top repositories
                async with session.get(
                    f"{self.base_url}/users/{username}/repos",
                    params={"sort": "stars", "per_page": 10, "direction": "desc"},
                    headers={"Accept": "application/vnd.github.v3+json"},
                    timeout=aiohttp.ClientTimeout(total=10),
                ) as resp:
                    repos_data = await resp.json() if resp.status == 200 else []
            
            # Parse repositories
            repositories = []
            for repo in (repos_data if isinstance(repos_data, list) else []):
                repositories.append(GitHubRepository(
                    name=repo.get("name", ""),
                    description=repo.get("description", "") or "",
                    url=repo.get("html_url", ""),
                    stars=repo.get("stargazers_count", 0),
                    forks=repo.get("forks_count", 0),
                    language=repo.get("language", "") or "",
                    topics=repo.get("topics", []),
                    is_fork=repo.get("fork", False),
                ))
            
            # Build profile
            profile = GitHubProfile(
                username=username,
                name=user_data.get("name"),
                bio=user_data.get("bio"),
                follower_count=user_data.get("followers", 0),
                following_count=user_data.get("following", 0),
                public_repo_count=user_data.get("public_repos", 0),
                location=user_data.get("location"),
                blog_url=user_data.get("blog"),
                twitter=user_data.get("twitter_username"),
                email=user_data.get("email"),
                created_at=datetime.fromisoformat(user_data["created_at"].replace("Z", "+00:00")) if user_data.get("created_at") else None,
                repositories=repositories,
            )
            
            logger.info(f"Successfully scraped GitHub profile: {username} ({profile.public_repo_count} repos, {profile.total_stars} stars)")
            return profile
            
        except Exception as e:
            logger.error(f"Error scraping GitHub profile {username}: {str(e)}")
            return None
    
    def extract_primary_languages(self, repositories: List[GitHubRepository]) -> Dict[str, int]:
        """Extract primary programming languages used.
        
        Args:
            repositories: List of repositories
            
        Returns:
            Dict of {language: repo_count}
        """
        language_counts = {}
        
        for repo in repositories:
            if repo.language:
                language_counts[repo.language] = language_counts.get(repo.language, 0) + 1
        
        # Sort by frequency
        return dict(sorted(language_counts.items(), key=lambda x: x[1], reverse=True))
    
    def extract_expertise_areas(self, repositories: List[GitHubRepository]) -> Dict[str, float]:
        """Infer expertise areas from repository topics and languages.
        
        Args:
            repositories: List of repositories
            
        Returns:
            Dict of {area: confidence_score (0.0-1.0)}
        """
        expertise = {}
        
        # Collect all topics
        all_topics = []
        for repo in repositories:
            all_topics.extend(repo.topics)
        
        # Count topic frequency
        topic_counts = {}
        for topic in all_topics:
            topic_counts[topic] = topic_counts.get(topic, 0) + 1
        
        # Convert to confidence scores
        max_count = max(topic_counts.values()) if topic_counts else 1
        for topic, count in topic_counts.items():
            expertise[topic] = count / max_count
        
        # Sort by score
        return dict(sorted(expertise.items(), key=lambda x: x[1], reverse=True))
    
    def estimate_skill_level(self, profile: GitHubProfile) -> str:
        """Estimate skill level based on repository stars and activity.
        
        Args:
            profile: GitHubProfile
            
        Returns:
            "beginner", "intermediate", "advanced", or "expert"
        """
        if not profile.repositories:
            return "unknown"
        
        avg_stars = profile.avg_stars_per_repo
        
        # Estimation based on average stars per repo
        if avg_stars >= 1000:
            return "expert"
        elif avg_stars >= 100:
            return "advanced"
        elif avg_stars >= 10:
            return "intermediate"
        else:
            return "beginner"
    
    def calculate_contribution_score(self, profile: GitHubProfile) -> float:
        """Calculate overall contribution score.
        
        Args:
            profile: GitHubProfile
            
        Returns:
            Score from 0.0-1.0
        """
        # Scoring factors:
        # 1. Total stars (0-0.4)
        stars_score = min(0.4, profile.total_stars / 1000)
        
        # 2. Repository count (0-0.3)
        repos_score = min(0.3, profile.public_repo_count / 100)
        
        # 3. Followers (0-0.3)
        followers_score = min(0.3, profile.follower_count / 1000)
        
        total = stars_score + repos_score + followers_score
        return min(1.0, total)


async def scrape_github_profile(username: str) -> Optional[Dict]:
    """Convenience function to scrape GitHub profile.
    
    Args:
        username: GitHub username
        
    Returns:
        Profile data dict or None
    """
    scraper = GitHubScraper()
    profile = await scraper.scrape_profile(username)
    
    if profile:
        return {
            "username": profile.username,
            "name": profile.name,
            "repos": profile.public_repo_count,
            "followers": profile.follower_count,
            "stars": profile.total_stars,
            "skill_level": scraper.estimate_skill_level(profile),
            "contribution_score": scraper.calculate_contribution_score(profile),
        }
    return None
