package ui.screens
{
	import flash.desktop.NativeApplication;
	import flash.desktop.SystemIdleMode;
	import flash.display.StageOrientation;
	import flash.events.Event;
	import flash.events.TimerEvent;
	import flash.system.System;
	import flash.text.TextField;
	import flash.text.TextFormat;
	import flash.utils.Timer;
	import flash.utils.getTimer;
	
	import database.BgReading;
	import database.BlueToothDevice;
	import database.CommonSettings;
	
	import events.FollowerEvent;
	import events.TransmitterServiceEvent;
	
	import feathers.controls.DragGesture;
	import feathers.controls.Label;
	import feathers.controls.LayoutGroup;
	import feathers.controls.ScrollPolicy;
	import feathers.events.FeathersEventType;
	import feathers.layout.AnchorLayout;
	import feathers.layout.AnchorLayoutData;
	import feathers.layout.HorizontalAlign;
	import feathers.layout.VerticalAlign;
	import feathers.layout.VerticalLayout;
	import feathers.themes.BaseMaterialDeepGreyAmberMobileTheme;
	import feathers.themes.MaterialDeepGreyAmberMobileThemeIcons;
	
	import model.ModelLocator;
	
	import services.NightscoutService;
	import services.TransmitterService;
	
	import starling.core.Starling;
	import starling.display.DisplayObject;
	import starling.events.Event;
	import starling.events.ResizeEvent;
	import starling.events.Touch;
	import starling.events.TouchEvent;
	import starling.events.TouchPhase;
	import starling.utils.Align;
	import starling.utils.SystemUtil;
	
	import treatments.TreatmentsManager;
	
	import ui.AppInterface;
	import ui.chart.GlucoseFactory;
	import ui.chart.GraphLayoutFactory;
	import ui.screens.display.LayoutFactory;
	
	import utils.Constants;
	import utils.DeviceInfo;
	import utils.GlucoseHelper;
	import utils.TimeSpan;
	
	[ResourceBundle("fullscreenglucosescreen")]
	[ResourceBundle("chartscreen")]

	public class FullScreenGlucoseScreen extends BaseSubScreen
	{
		/* Constants */
		private const TIME_6_MINUTES:int = 6 * 60 * 1000;
		private const TIME_16_MINUTES:int = 16 * 60 * 1000;
		
		/* Display Objects */
		private var glucoseDisplay:Label;
		private var timeAgoDisplay:Label;
		private var slopeDisplay:Label;
		private var container:LayoutGroup;
		private var IOBCOBDisplay:Label;

		/* Properties */
		private var oldColor:uint = 0xababab;
		private var newColor:uint = 0xEEEEEE;
		private var glucoseFontSize:Number;
		private var infoFontSize:Number;
		private var glucoseList:Array;
		private var latestGlucoseValue:Number;
		private var latestGlucoseOutput:String;
		private var latestGlucoseTimestamp:Number = 0;
		private var latestGlucoseColor:uint;
		private var latestGlucoseSlopeArrow:String;
		private var previousGlucoseValue:Number;
		private var previousGlucoseTimestamp:Number = 0;
		private var glucoseUnit:String;
		private var updateTimer:Timer;
		private var latestGlucoseSlopeOutput:String;
		private var userBGFontMultiplier:Number;
		private var userTimeAgoFontMultiplier:Number;
		private var timeAgoOutput:String;
		private var timeAgoColor:uint;
		private var latestSlopeInfoColor:uint;
		private var nowTimestamp:Number;
		private var latestGlucoseProperties:Object;
		private var latestGlucoseValueFormatted:Number;
		private var previousGlucoseValueFormatted:Number;
		private var touchTimer:Number;
		
		[Embed(source="/assets/theme/fonts/OpenSans-Bold.ttf", embedAsCFF="false", fontWeight="bold", fontName="OpenSansBold", fontFamily="OpenSansBold", mimeType="application/x-font")]
		private static const OPEN_SANS_BOLD:Class;
		
		public function FullScreenGlucoseScreen() 
		{
			super();
			styleNameList.add( BaseMaterialDeepGreyAmberMobileTheme.THEME_STYLE_NAME_HEADER_WITH_SHADOW );
			styleNameList.add( BaseMaterialDeepGreyAmberMobileTheme.THEME_STYLE_NAME_PANEL_WITHOUT_PADDING );
		}
		
		override protected function initialize():void 
		{
			super.initialize();
			
			addEventListener(FeathersEventType.CREATION_COMPLETE, onCreation);
			Starling.current.stage.addEventListener(starling.events.Event.RESIZE, onStarlingResize);
			this.horizontalScrollPolicy = ScrollPolicy.OFF;
			
			setupHeader();
			setupLayout();
			setupInitialContent();
			setupContent();
			setupEventListeners();
			adjustMainMenu();
			updateInfo();
		}
		
		/**
		 * Functionality
		 */
		private function setupHeader():void
		{
			/* Set Header Title */
			if (Constants.deviceModel != DeviceInfo.IPHONE_2G_3G_3GS_4_4S_ITOUCH_2_3_4 && Constants.deviceModel != DeviceInfo.IPHONE_5_5S_5C_SE_ITOUCH_5_6)
				title = ModelLocator.resourceManagerInstance.getString('fullscreenglucosescreen','screen_title');
			else
				title = ModelLocator.resourceManagerInstance.getString('fullscreenglucosescreen','screen_title_small');
			
			/* Set Header Icon */
			icon = getScreenIcon(MaterialDeepGreyAmberMobileThemeIcons.fullscreenTexture);
			iconContainer = new <DisplayObject>[icon];
			headerProperties.rightItems = iconContainer;
		}
		
		private function setupInitialContent():void
		{			
			//Glucose Unit
			if (CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_DO_MGDL) == "true") 
				glucoseUnit = "mg/dl";
			else
				glucoseUnit = "mmol/L";
			
			//Font Size
			userBGFontMultiplier = Number(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_CHART_BG_FONT_SIZE));
			userTimeAgoFontMultiplier = Number(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_CHART_TIMEAGO_FONT_SIZE));
		
			//User's Readings
			glucoseList = ModelLocator.bgReadings;
			
			//Calculate Values
			calculateValues();
		}
		
		private function setupContent():void
		{
			/* Determine Font Sizes */
			calculateFontSize();
			
			/* Glucose Display Label */
			glucoseDisplay = LayoutFactory.createLabel(latestGlucoseOutput, HorizontalAlign.CENTER, VerticalAlign.MIDDLE, glucoseFontSize, true);
			glucoseDisplay.fontStyles.color = latestGlucoseColor;
			glucoseDisplay.fontStyles.leading = getLeading(latestGlucoseSlopeArrow);
			container.addChild(glucoseDisplay);
			
			/* TimeAgo Display Label */
			timeAgoDisplay = LayoutFactory.createLabel(timeAgoOutput, HorizontalAlign.LEFT, VerticalAlign.MIDDLE, infoFontSize, false, timeAgoColor);
			timeAgoDisplay.width = 350;
			timeAgoDisplay.y = 10;
			timeAgoDisplay.x = Constants.deviceModel == DeviceInfo.IPHONE_X && !Constants.isPortrait && Constants.currentOrientation == StageOrientation.ROTATED_RIGHT ? 40 : 10;
			timeAgoDisplay.validate();
			addChild(timeAgoDisplay);
			
			/* Slope Display Label */
			slopeDisplay = LayoutFactory.createLabel(latestGlucoseSlopeOutput != "" && latestGlucoseSlopeOutput != null ? latestGlucoseSlopeOutput + " " + GlucoseHelper.getGlucoseUnit() : "", HorizontalAlign.RIGHT, VerticalAlign.MIDDLE, infoFontSize, false, latestSlopeInfoColor);
			slopeDisplay.width = 300;
			slopeDisplay.validate();
			slopeDisplay.x = Constants.stageWidth - slopeDisplay.width - (Constants.deviceModel == DeviceInfo.IPHONE_X && !Constants.isPortrait && Constants.currentOrientation == StageOrientation.ROTATED_LEFT ? 40 : 10);
			slopeDisplay.y = timeAgoDisplay.y;
			addChild(slopeDisplay);
			
			/* IOB/COB Display Label */
			var now:Number = new Date().valueOf();
			IOBCOBDisplay = GraphLayoutFactory.createChartStatusText(timeAgoColor != 0 ? "IOB: " + GlucoseFactory.formatIOB(TreatmentsManager.getTotalIOB(now)) + "  COB: " + GlucoseFactory.formatCOB(TreatmentsManager.getTotalCOB(now)) : "", timeAgoColor, infoFontSize, Align.CENTER, false, Constants.stageWidth);
			var IOBCOBLayoutData:AnchorLayoutData = new AnchorLayoutData();
			if (Constants.deviceModel != DeviceInfo.IPHONE_X)
				IOBCOBLayoutData.bottom = 10;
			else
				IOBCOBLayoutData.bottom = 20;
			IOBCOBDisplay.layoutData = IOBCOBLayoutData;
			addChild(IOBCOBDisplay);
			
			/* Setup Timer */
			updateTimer = new Timer(15 * 1000);
			updateTimer.addEventListener(TimerEvent.TIMER, onUpdateTimer, false, 0, true);
			updateTimer.start();
		}
		
		private function setupEventListeners():void
		{
			TransmitterService.instance.addEventListener(TransmitterServiceEvent.BGREADING_EVENT, onBgReadingReceived, false, 0, true);
			NightscoutService.instance.addEventListener(FollowerEvent.BG_READING_RECEIVED, onBgReadingReceived, false, 0, true);
			this.addEventListener(TouchEvent.TOUCH, onTouch);
		}
		
		private function updateInfo():void
		{
			/* Determine Font Sizes */
			calculateFontSize();
			
			/* Glucose Display Label */
			glucoseDisplay.text = latestGlucoseOutput;
			glucoseDisplay.fontStyles.leading = getLeading(latestGlucoseSlopeArrow);
			glucoseDisplay.fontStyles.color = latestGlucoseColor;
			glucoseDisplay.fontStyles.size = glucoseFontSize;
			
			/* TimeAgo Display Label */
			timeAgoDisplay.text = timeAgoOutput;
			timeAgoDisplay.fontStyles.color = timeAgoColor;
			
			/* Slope Display Label */
			slopeDisplay.text = latestGlucoseSlopeOutput != "" && latestGlucoseSlopeOutput != null ? latestGlucoseSlopeOutput + " " + GlucoseHelper.getGlucoseUnit() : "";
			slopeDisplay.fontStyles.color = latestSlopeInfoColor;
			
			/* IOB / COB Display Label */
			var now:Number = new Date().valueOf();
			IOBCOBDisplay.fontStyles.color = timeAgoColor;
			IOBCOBDisplay.text = "IOB: " + GlucoseFactory.formatIOB(TreatmentsManager.getTotalIOB(now)) + "  COB: " + GlucoseFactory.formatCOB(TreatmentsManager.getTotalCOB(now));
		}
		
		private function calculateValues():void
		{
			nowTimestamp = new Date().valueOf();
			
			//Populate Internal Variables
			if (glucoseList == null || glucoseList.length == 0)
			{
				//NO BGREADINGS AVAILABLE
				latestGlucoseOutput = "---";
				latestGlucoseColor = oldColor;
				latestGlucoseSlopeArrow = "";
				latestGlucoseSlopeOutput = "";
				latestSlopeInfoColor = oldColor;
				timeAgoOutput = "";
				timeAgoColor = oldColor
				
			}
			else if (glucoseList.length == 1)
			{
				if (glucoseList[glucoseList.length - 1] == null)
				{
					//NO BGREADINGS AVAILABLE
					latestGlucoseOutput = "---";
					latestGlucoseColor = oldColor;
					latestGlucoseSlopeArrow = "";
					latestGlucoseSlopeOutput = "";
					latestSlopeInfoColor = oldColor;
					timeAgoOutput = "";
					timeAgoColor = oldColor
					return;
				}
				
				//Timestamp
				latestGlucoseTimestamp = glucoseList[glucoseList.length - 1].timestamp;
				
				//BG Value
				if (glucoseList[glucoseList.length - 1] == null)
					return;
				
				latestGlucoseValue = glucoseList[glucoseList.length - 1].calculatedValue;
				
				if (latestGlucoseValue < 40) latestGlucoseValue = 40;
				else if (latestGlucoseValue > 400) latestGlucoseValue = 400;
				
				if (nowTimestamp - latestGlucoseTimestamp <= TIME_16_MINUTES)
				{
					latestGlucoseProperties = GlucoseFactory.getGlucoseOutput(latestGlucoseValue);
					latestGlucoseOutput = latestGlucoseProperties.glucoseOutput;
					latestGlucoseValueFormatted = latestGlucoseProperties.glucoseValueFormatted;
					if (nowTimestamp - latestGlucoseTimestamp < TIME_6_MINUTES)
						latestGlucoseColor = GlucoseFactory.getGlucoseColor(latestGlucoseValue);
					else
						latestGlucoseColor = oldColor;
				}
				else 
				{
					latestGlucoseOutput = "---";
					latestGlucoseColor = oldColor;
				}
				
				//Slope
				latestGlucoseSlopeArrow = "";
				latestGlucoseSlopeOutput = "";
				latestSlopeInfoColor = oldColor;
				
				//Time Ago
				timeAgoOutput = TimeSpan.formatHoursMinutesFromSecondsChart((nowTimestamp - latestGlucoseTimestamp)/1000, false, false);
				timeAgoOutput != ModelLocator.resourceManagerInstance.getString('chartscreen','now') ? timeAgoOutput += " " + ModelLocator.resourceManagerInstance.getString('chartscreen','time_ago_suffix') : timeAgoOutput += "";
				if (nowTimestamp - latestGlucoseTimestamp < TIME_6_MINUTES)
					timeAgoColor = newColor;
				else
					timeAgoColor = oldColor;
			}
			else if (glucoseList.length > 1)
			{
				if (glucoseList[glucoseList.length - 2] == null || glucoseList[glucoseList.length - 1] == null)
					return;
				
				//Timestamps
				previousGlucoseTimestamp = glucoseList[glucoseList.length - 2].timestamp;
				latestGlucoseTimestamp = glucoseList[glucoseList.length - 1].timestamp;
				
				//BG Values
				//Previous
				previousGlucoseValue = glucoseList[glucoseList.length - 2].calculatedValue;
				previousGlucoseValueFormatted = GlucoseFactory.getGlucoseOutput(previousGlucoseValue).glucoseValueFormatted;
				if (previousGlucoseValue < 40) previousGlucoseValue = 40;
				else if (previousGlucoseValue > 400) previousGlucoseValue = 400;
				
				//Latest
				latestGlucoseValue = glucoseList[glucoseList.length - 1].calculatedValue;
				if (latestGlucoseValue < 40) latestGlucoseValue = 40;
				else if (latestGlucoseValue > 400) latestGlucoseValue = 400;
				
				if (nowTimestamp - latestGlucoseTimestamp <= TIME_16_MINUTES)
				{
					latestGlucoseProperties = GlucoseFactory.getGlucoseOutput(latestGlucoseValue);
					latestGlucoseOutput = latestGlucoseProperties.glucoseOutput;
					latestGlucoseValueFormatted = latestGlucoseProperties.glucoseValueFormatted;
					if (nowTimestamp - latestGlucoseTimestamp < TIME_6_MINUTES)
						latestGlucoseColor = GlucoseFactory.getGlucoseColor(latestGlucoseValue);
					else 
						latestGlucoseColor = oldColor;
				}
				else
				{
					latestGlucoseOutput = "---";
					latestGlucoseColor = oldColor;
				}
				
				/* SLOPE */
				if (nowTimestamp - latestGlucoseTimestamp > TIME_16_MINUTES || latestGlucoseTimestamp - previousGlucoseTimestamp > TIME_16_MINUTES)
					latestGlucoseSlopeOutput = "";
				else if (latestGlucoseTimestamp - previousGlucoseTimestamp < TIME_16_MINUTES)
				{
					latestGlucoseSlopeOutput = GlucoseFactory.getGlucoseSlope
						(
							previousGlucoseValue, 
							previousGlucoseValueFormatted, 
							latestGlucoseValue, 
							latestGlucoseValueFormatted
						);
					
					if (nowTimestamp - latestGlucoseTimestamp < TIME_6_MINUTES)
						latestSlopeInfoColor = newColor;
					else
						latestSlopeInfoColor = oldColor;
				}
				
				//Arrow
				if (nowTimestamp - latestGlucoseTimestamp > TIME_16_MINUTES || latestGlucoseTimestamp - previousGlucoseTimestamp > TIME_16_MINUTES)
					latestGlucoseSlopeArrow = "";
				else if (latestGlucoseTimestamp - previousGlucoseTimestamp <= TIME_16_MINUTES)
				{
					if ((glucoseList[glucoseList.length - 1] as BgReading).hideSlope)
						latestGlucoseSlopeArrow = "\u21C4";
					else 
						latestGlucoseSlopeArrow = (glucoseList[glucoseList.length - 1] as BgReading).slopeArrow();
				}
				
				/* TIMEAGO */
				nowTimestamp = new Date().valueOf();
				var differenceInSec:Number = (nowTimestamp - latestGlucoseTimestamp) / 1000;
				timeAgoOutput = TimeSpan.formatHoursMinutesFromSecondsChart(differenceInSec, false, false);
				timeAgoOutput != ModelLocator.resourceManagerInstance.getString('chartscreen','now') ? timeAgoOutput += " " + ModelLocator.resourceManagerInstance.getString('chartscreen','time_ago_suffix') : timeAgoOutput += "";
				
				if (nowTimestamp - latestGlucoseTimestamp < TIME_6_MINUTES)
					timeAgoColor = newColor;
				else
					timeAgoColor = oldColor;
			}
			
			if (Constants.isPortrait)
				latestGlucoseOutput = latestGlucoseOutput + "\n" + latestGlucoseSlopeArrow;
			else
				latestGlucoseOutput = latestGlucoseOutput + " " + latestGlucoseSlopeArrow;
			
			/* IOB / COB Display Label */
			if (IOBCOBDisplay != null)
			{
				var now:Number = new Date().valueOf();
				IOBCOBDisplay.fontStyles.color = timeAgoColor;
				IOBCOBDisplay.text = "IOB: " + GlucoseFactory.formatIOB(TreatmentsManager.getTotalIOB(now)) + "  COB: " + GlucoseFactory.formatCOB(TreatmentsManager.getTotalCOB(now));
			}
		}
		
		private function getLeading(arrow:String):Number
		{
			var leading:Number = -150 / 2.5;
			
			if (arrow != null)
			{
				if (arrow.indexOf("\u21C4") != -1 || arrow.indexOf("\u2192") != -1) //FLAT
					leading = -glucoseFontSize / 2;
				else if (arrow.indexOf("\u2198") != -1 || arrow.indexOf("\u2197") != -1) //45º Down/UP
					leading = -glucoseFontSize / 3;
				else if (arrow.indexOf("\u2193") != -1 || arrow.indexOf("\u2191") != -1) //Down/Up
				{
					if (Constants.deviceModel == DeviceInfo.IPHONE_2G_3G_3GS_4_4S_ITOUCH_2_3_4)
						leading = -glucoseFontSize / 2.5;
					else
						leading = -glucoseFontSize / 3;
				}
			}
			
			return leading;
		}
		
		private function setupLayout():void
		{
			/* Parent Class Layout */
			layout = new AnchorLayout(); 
			
			/* Create Display Object's Container and Corresponding Vertical Layout and Centered LayoutData */
			container = new LayoutGroup();
			var containerLayout:VerticalLayout = new VerticalLayout();
			containerLayout.gap = -50;
			containerLayout.horizontalAlign = HorizontalAlign.CENTER;
			containerLayout.verticalAlign = VerticalAlign.MIDDLE;
			container.layout = containerLayout;
			var containerLayoutData:AnchorLayoutData = new AnchorLayoutData();
			containerLayoutData.horizontalCenter = 0;
			containerLayoutData.verticalCenter = 0;
			container.layoutData = containerLayoutData;
			this.addChild( container );
		}
		
		private function adjustMainMenu():void
		{
			AppInterface.instance.menu.selectedIndex = -1;
		}
		
		private function calculateFontSize():void
		{
			if (latestGlucoseOutput == null || latestGlucoseSlopeArrow == null)
				return;
			
			var sNativeFormat:flash.text.TextFormat = new flash.text.TextFormat();
			sNativeFormat.font = "OpenSansBold";
			sNativeFormat.bold = true;
			sNativeFormat.color = 0xFFFFFF;
			sNativeFormat.size = 600;
			sNativeFormat.leading = getLeading(latestGlucoseSlopeArrow);
			
			var formattedGlucoseOutput:String = Constants.isPortrait ? latestGlucoseOutput.substring(0, latestGlucoseOutput.indexOf("\n")) : latestGlucoseOutput.substring(0, latestGlucoseOutput.indexOf(" "));
			if (formattedGlucoseOutput == null) formattedGlucoseOutput = "";
			if (!Constants.isPortrait) formattedGlucoseOutput += " -->";
			if (Constants.isPortrait && (latestGlucoseSlopeArrow.indexOf("\u2197") != -1 || latestGlucoseSlopeArrow.indexOf("\u2198") != -1 || latestGlucoseSlopeArrow.indexOf("\u2191") != -1 || latestGlucoseSlopeArrow.indexOf("\u2193") != -1))
				formattedGlucoseOutput += "\n |";
			
			var nativeTextField:flash.text.TextField = new flash.text.TextField();
			nativeTextField.defaultTextFormat = sNativeFormat;
			nativeTextField.width  = Constants.stageWidth;
			nativeTextField.height = Constants.stageHeight;
			nativeTextField.selectable = false;
			nativeTextField.multiline = true;
			nativeTextField.wordWrap = false;
			nativeTextField.embedFonts = true;
			nativeTextField.text = formattedGlucoseOutput;
			
			if (sNativeFormat == null) return;
			
			var textFormat:flash.text.TextFormat = sNativeFormat;
			var maxTextWidth:int  = Constants.stageWidth - (Constants.isPortrait ? Constants.stageWidth * 0.2 : Constants.stageWidth * 0.1);
			var maxTextHeight:int = Constants.stageHeight - Constants.headerHeight;
			if (Constants.deviceModel == DeviceInfo.IPHONE_X && !Constants.isPortrait)
				maxTextHeight -= maxTextHeight * 0.35;
			
			if (isNaN(maxTextWidth) || isNaN(maxTextHeight)) return;
			
			var size:Number = Number(textFormat.size);
			
			while (nativeTextField.textWidth > maxTextWidth || nativeTextField.textHeight > maxTextHeight)
			{
				if (size <= 4) break;
				
				textFormat.size = size--;
				nativeTextField.defaultTextFormat = textFormat;
				
				nativeTextField.text = formattedGlucoseOutput;
			}
			
			var deviceFontMultiplier:Number = DeviceInfo.getFontMultipier();
			infoFontSize = 22 * deviceFontMultiplier * userTimeAgoFontMultiplier;
			
			glucoseFontSize =  Number(textFormat.size);
			if (isNaN(glucoseFontSize)) glucoseFontSize = 130;
		}
		
		/**
		 * Event Listeners
		 */
		private function onBgReadingReceived(e:flash.events.Event):void
		{
			//Get latest BGReading
			var latestBgReading:BgReading;
			if (!BlueToothDevice.isFollower())
				latestBgReading = BgReading.lastNoSensor();
			else
				latestBgReading = BgReading.lastWithCalculatedValue();
			
			//If the latest BGReading is null, stop execution
			if (latestBgReading == null)
				return;
			
			//Reset Update Timer
			if (updateTimer == null)
			{
				updateTimer = new Timer(60 * 1000);
				updateTimer.addEventListener(TimerEvent.TIMER, onUpdateTimer, false, 0, true);
			}
			else
			{
				updateTimer.stop();
				updateTimer.delay = 60 * 1000;
				updateTimer.start();
			}
			
			//Calculate Glucose Values and Update Labels
			SystemUtil.executeWhenApplicationIsActive( calculateValues );
			SystemUtil.executeWhenApplicationIsActive( updateInfo );
		}
		
		private function onUpdateTimer(event:TimerEvent):void
		{
			if (latestGlucoseTimestamp != 0 && SystemUtil.isApplicationActive)
			{
				/* Time Ago */
				var nowTimestamp:Number = new Date().valueOf();
				var differenceInSec:Number = (nowTimestamp - latestGlucoseTimestamp) / 1000;
				timeAgoOutput = TimeSpan.formatHoursMinutesFromSecondsChart(differenceInSec, false, false);
				timeAgoOutput != ModelLocator.resourceManagerInstance.getString('chartscreen','now') ? timeAgoOutput += " " + ModelLocator.resourceManagerInstance.getString('chartscreen','time_ago_suffix') : timeAgoOutput += "";
				timeAgoDisplay.text = timeAgoOutput;
				
				if (nowTimestamp - latestGlucoseTimestamp < TIME_6_MINUTES)
					timeAgoColor = newColor;
				else
					timeAgoColor = oldColor;
				
				timeAgoDisplay.fontStyles.color = timeAgoColor;
				
				if ( nowTimestamp - latestGlucoseTimestamp > TIME_16_MINUTES )
				{
					//Glucose Value
					latestGlucoseOutput = "---";
					glucoseDisplay.text = latestGlucoseOutput;
					glucoseDisplay.fontStyles.color = oldColor;
					
					/* Slope Display Label */
					latestGlucoseSlopeOutput = "";
					slopeDisplay.text = latestGlucoseSlopeOutput != "" && latestGlucoseSlopeOutput != null ? latestGlucoseSlopeOutput  + " " + GlucoseHelper.getGlucoseUnit() : "";
					
					//Slope Arrow
					latestGlucoseSlopeArrow = "";
					
					glucoseDisplay.fontStyles.leading = getLeading(latestGlucoseSlopeArrow);
				}
				else if ( nowTimestamp - latestGlucoseTimestamp > TIME_6_MINUTES )
				{
					glucoseDisplay.fontStyles.color = oldColor;
					slopeDisplay.fontStyles.color = oldColor;
				}
				
				
				if (Constants.isPortrait)
					latestGlucoseOutput = latestGlucoseOutput + "\n" + latestGlucoseSlopeArrow;
				else
					latestGlucoseOutput = latestGlucoseOutput + " " + latestGlucoseSlopeArrow;
			}
			
			/* IOB / COB Display Label */
			if (IOBCOBDisplay != null && SystemUtil.isApplicationActive)
			{
				var now:Number = new Date().valueOf();
				IOBCOBDisplay.fontStyles.color = timeAgoColor;
				IOBCOBDisplay.text = "IOB: " + GlucoseFactory.formatIOB(TreatmentsManager.getTotalIOB(now)) + "  COB: " + GlucoseFactory.formatCOB(TreatmentsManager.getTotalCOB(now));
			}
		}
		
		private function onTouch (e:TouchEvent):void
		{
			var touch:Touch = e.getTouch(stage);
			if(touch != null && touch.phase == TouchPhase.BEGAN)
			{
				touchTimer = getTimer();
				addEventListener(starling.events.Event.ENTER_FRAME, onHold);
			}
			
			if(touch != null && touch.phase == TouchPhase.ENDED)
			{
				touchTimer = Number.NaN;
				removeEventListener(starling.events.Event.ENTER_FRAME, onHold);
			}
		}
		
		private function onHold(e:starling.events.Event):void
		{
			if (isNaN(touchTimer))
				return;
			
			if (getTimer() - touchTimer > 1000)
			{
				touchTimer = Number.NaN;
				removeEventListener(starling.events.Event.ENTER_FRAME, onHold);
				
				//Pop screen
				onBackButtonTriggered(null);
			}
		}
		
		override protected function onBackButtonTriggered(event:starling.events.Event):void
		{
			//Pop this screen off
			dispatchEventWith(starling.events.Event.COMPLETE);
			
			//Activate menu drag gesture
			AppInterface.instance.drawers.openGesture = DragGesture.EDGE;
			
			//Deactivate Keep Awake
			NativeApplication.nativeApplication.systemIdleMode = SystemIdleMode.NORMAL;
			Constants.noLockEnabled = false;
		}
		
		private function onStarlingResize(event:ResizeEvent):void 
		{
			width = Constants.stageWidth;
			
			if (IOBCOBDisplay != null)
				IOBCOBDisplay.width = Constants.stageWidth;
			
			//Adjust header for iPhone X
			onCreation(null);
			
			//Adjust label position
			if (timeAgoDisplay != null && slopeDisplay != null)
			{
				timeAgoDisplay.x = Constants.deviceModel == DeviceInfo.IPHONE_X && !Constants.isPortrait && Constants.currentOrientation == StageOrientation.ROTATED_RIGHT ? 40 : 10;
				slopeDisplay.x = Constants.stageWidth - slopeDisplay.width - (Constants.deviceModel == DeviceInfo.IPHONE_X && !Constants.isPortrait && Constants.currentOrientation == StageOrientation.ROTATED_LEFT ? 40 : 10);
			}
			
			SystemUtil.executeWhenApplicationIsActive( calculateValues );
			SystemUtil.executeWhenApplicationIsActive( updateInfo );
		}
		
		private function onCreation(event:starling.events.Event):void
		{
			if (Constants.deviceModel == DeviceInfo.IPHONE_X && this.header != null)
			{
				if (Constants.isPortrait)
				{
					this.header.height = 108;
					this.header.maxHeight = 108;	
				}
				else
				{
					this.header.height = 78;
					this.header.maxHeight = 78;
				}
			}
		}
		
		override protected function onTransitionInComplete(e:starling.events.Event):void
		{
			//Swipe to pop functionality
			AppInterface.instance.navigator.isSwipeToPopEnabled = false;
			AppInterface.instance.drawers.openGesture = DragGesture.NONE;
		}
		
		/**
		 * Utility
		 */
		override protected function draw():void 
		{
			super.draw();
			icon.x = Constants.stageWidth - icon.width - BaseMaterialDeepGreyAmberMobileTheme.defaultPanelPadding;
		}
		
		override public function dispose():void
		{
			Starling.current.stage.removeEventListener(starling.events.Event.RESIZE, onStarlingResize);
			TransmitterService.instance.removeEventListener(TransmitterServiceEvent.BGREADING_EVENT, onBgReadingReceived);
			NightscoutService.instance.removeEventListener(FollowerEvent.BG_READING_RECEIVED, onBgReadingReceived);
			this.removeEventListener(TouchEvent.TOUCH, onTouch);
			
			if(updateTimer != null)
			{
				updateTimer.stop();
				updateTimer.removeEventListener(TimerEvent.TIMER, onUpdateTimer);
				updateTimer = null;
			}
			
			if(glucoseDisplay != null)
			{
				glucoseDisplay.removeFromParent();
				glucoseDisplay.dispose();
				glucoseDisplay = null;
			}
			
			if (slopeDisplay != null)
			{
				slopeDisplay.removeFromParent();
				slopeDisplay.dispose();
				slopeDisplay = null;
			}
			
			if(timeAgoDisplay != null)
			{
				timeAgoDisplay.removeFromParent();
				timeAgoDisplay.dispose();
				timeAgoDisplay = null;
			}
			
			if (IOBCOBDisplay != null)
			{
				IOBCOBDisplay.removeFromParent();
				IOBCOBDisplay.dispose();
				IOBCOBDisplay = null;
			}
			
			if(container != null)
			{
				container.removeFromParent();
				container.dispose();
				container = null;
			}
			
			super.dispose();
			
			System.pauseForGCIfCollectionImminent(0);
		}
	}
}