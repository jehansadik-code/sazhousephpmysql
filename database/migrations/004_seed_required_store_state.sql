-- Seed only missing required state records. Existing catalog, content, stock,
-- coupons, settings, revisions, and timestamps are never overwritten.
INSERT IGNORE INTO store_state (`key`, value) VALUES
('products', JSON_ARRAY()),
('product_types', JSON_ARRAY('tee','hoodie','cap','jacket','pants','bag','other')),
('coupons', JSON_ARRAY()),
('settings', JSON_OBJECT('dhaka',80,'outside',150,'freeThreshold',3000,'payments',JSON_OBJECT('cod',true,'bkash',true,'nagad',true,'card',true),'bkashNumber','','nagadNumber','')),
('site_content', JSON_OBJECT('announcement','Free delivery on orders over Tk 3,000 - Designed in Dhaka','heroEyebrow','WEAR YOUR VISION','heroTitle','STYLE MEETS\nIDENTITY','heroText','SAZ House brings you premium streetwear that speaks your style, your story, your vibe.','heroButton','SHOP NOW','aboutStory','SAZ House started with a simple idea: everyday clothing should feel like you. We make considered streetwear with confident design, comfortable fits, and quality you can count on.','footerText','Streetwear made for your everyday. Be part of the SAZ House movement.','contactEmail','support@sazhouse.com','contactPhone','+880 1700-000000','contactLocation','Dhaka, Bangladesh','logoPath','assets/images/brand/logo.png')),
('page_products', JSON_OBJECT()),
('home_categories', JSON_ARRAY(JSON_OBJECT('label','Men','href','shop.html?department=men','image',''),JSON_OBJECT('label','Women','href','shop.html?department=women','image',''),JSON_OBJECT('label','Shoes','href','shop.html?category=Shoes','image',''),JSON_OBJECT('label','Bags','href','shop.html?category=Bags','image','')));
